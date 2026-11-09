import AppKit

/// Automatic switching (SPEC 6.2): feeds AutoSwitcher the events it needs, waits for them to
/// settle, and switches the input when it says so. Picking a microphone by hand turns it off.
/// Every decision goes in the log.
@MainActor
final class AutoSwitchController {
    private let model: AppModel
    private let audio: AudioSystem
    private let config: ConfigStore
    private var switcher = AutoSwitcher()
    private var settleTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?

    /// An input change is sorted by who made it a moment after it arrives, because when a device
    /// connects, macOS can announce the new input before the new device (SPEC 6.2).
    private static let classifyDelay: Duration = .milliseconds(400)

    init(model: AppModel, audio: AudioSystem, config: ConfigStore, displays: DisplayMonitor, lid: LidMonitor) {
        self.model = model
        self.audio = audio
        self.config = config
        model.preferredOrderEnabled = config.preferredOrderEnabled
        model.lidClosed = lid.isClosed

        audio.onTopologyChange = { [weak self] in self?.topologyChanged() }
        audio.onInputChange = { [weak self] uid in self?.inputChanged(to: uid) }
        audio.onOutputChange.append { [weak self] in self?.somethingChanged() }
        displays.onChange = { [weak self] in self?.topologyChanged() }
        lid.onChange = { [weak self] closed in
            self?.model.lidClosed = closed
            self?.topologyChanged()
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                Log.info("Mac woke")
                self?.topologyChanged()
            }
        }
        // Edits in the Setups and Devices tabs call for a fresh decision.
        trackChanges { [weak self] in
            guard let self else { return }
            _ = (self.model.setups, self.model.knownDevices)
            self.somethingChanged()
        }
        if model.preferredOrderEnabled { Log.info("Automatic switching is on") }
    }

    // MARK: From the user

    /// The panel's toggle and General's checkbox. Turning it on decides at once.
    func setEnabled(_ on: Bool, reason: String? = nil) {
        guard on != model.preferredOrderEnabled else { return }
        config.preferredOrderEnabled = on
        config.saveOrLog()
        model.preferredOrderEnabled = on
        Log.info("Automatic switching turned \(on ? "on" : "off")" + (reason.map { ": \($0)" } ?? ""))
        if on { decide() }
    }

    /// A click in the panel, or a shortcut, switches now and turns automatic switching off
    /// (SPEC 6.2). `via` goes in the log: "the panel" or "a shortcut".
    func panelPicked(_ device: InputDevice, via: String = "the panel") {
        if model.preferredOrderEnabled, device.objectID != model.currentInputID {
            setEnabled(false, reason: "\(model.shownName(of: device)) picked with \(via)")
        }
        audio.select(device, reason: via == "the panel" ? "Panel" : "Shortcut")
    }

    // MARK: Events

    private func topologyChanged() {
        switcher.topologyChanged(at: .now)
        settleThenDecide()
    }

    private func somethingChanged() {
        switcher.somethingChanged(at: .now)
        settleThenDecide()
    }

    private func inputChanged(to uid: String?) {
        let time = Date()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.classifyDelay)
            self?.classify(uid, at: time)
        }
    }

    private func classify(_ uid: String?, at time: Date) {
        guard model.preferredOrderEnabled else { return }
        let name = uid.flatMap { uid in model.knownDevices.first { $0.uid == uid }?.shownName } ?? uid ?? "none"
        switch switcher.inputChanged(to: uid, at: time) {
        case .own:
            break
        case .macOS:
            Log.info("Auto: macOS switched to \(name) as something connected or disconnected; deciding again once things settle")
            settleThenDecide()
        case .manual:
            setEnabled(false, reason: "\(name) picked outside Tally Mic")
        }
    }

    // MARK: Deciding

    /// SPEC 6.2: wait until nothing has happened for 1.5 seconds, then decide once.
    private func settleThenDecide() {
        settleTask?.cancel()
        settleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(AutoSwitcher.settleTime))
            guard !Task.isCancelled, let self else { return }
            if self.switcher.isSettled(at: .now) {
                self.decide()
            } else {
                self.settleThenDecide()
            }
        }
    }

    private func decide() {
        guard model.preferredOrderEnabled else { return }
        let setup = model.activeSetup
        let decision = AutoSwitcher.decide(
            setup: setup, known: model.knownDevices, connected: model.inputs, lidClosed: model.lidClosed,
            outputUID: model.outputUID, currentUID: model.currentInput?.uid)
        guard case .switchTo(let device) = decision else { return }
        let from = model.currentInput.map(model.shownName) ?? "nothing"
        Log.info("Auto: \(setup.name) prefers \(model.shownName(of: device)); switching from \(from)")
        switcher.willSwitch(to: device.uid, at: .now)
        audio.select(device, reason: "Auto")
    }
}
