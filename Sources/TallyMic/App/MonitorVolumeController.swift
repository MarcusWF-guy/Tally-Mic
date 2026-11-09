import AppKit
import CoreAudio

/// SPEC 7.7: while the sound plays through a monitor whose volume macOS can't change, the
/// keyboard's volume keys change the monitor's own volume over its cable (DDC), with a volume
/// bubble like macOS's. Anywhere else the keys are left to macOS. Off until turned on in
/// Settings > General, and it needs Accessibility permission to catch the keys.
@MainActor
final class MonitorVolumeController {
    private let model: AppModel
    private let config: ConfigStore
    private let keys = VolumeKeyTap()
    private let hud = VolumeHUDController()

    /// The monitor the sound output belongs to, once found, and its volume as Tally Mic knows it.
    private var monitor: MonitorDDC?
    private var volume = MonitorVolume(level: 0.5)
    private var maxValue: UInt16 = 100
    /// The output being looked up, so a lookup that ends after the output changed again is dropped.
    private var lookingUp: String?
    private var accessObserver: NSObjectProtocol?
    /// Only the newest value is sent, so holding a key down doesn't queue up a backlog of writes.
    private var pendingValue: UInt16?
    private var isWriting = false

    private static let feedbackSound = "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff"

    init(model: AppModel, config: ConfigStore) {
        self.model = model
        self.config = config
        model.monitorVolumeEnabled = config.controlMonitorVolume
        keys.onPress = { [weak self] press in self?.handle(press) ?? false }
        if config.controlMonitorVolume { start(asking: false) }
    }

    func setEnabled(_ on: Bool) {
        guard on != model.monitorVolumeEnabled else { return }
        config.controlMonitorVolume = on
        config.saveOrLog()
        model.monitorVolumeEnabled = on
        Log.info("Monitor volume control turned \(on ? "on" : "off")")
        if on { start(asking: true) } else { stop() }
    }

    func outputChanged() {
        monitor = nil
        lookingUp = nil
        if keys.isRunning { lookUpMonitor() }
    }

    /// The Settings window came up: permission may have been given since the last check.
    func recheckAccess() {
        if model.monitorVolumeEnabled && !keys.isRunning && VolumeKeyTap.isAllowed { start(asking: false) }
    }

    // MARK: Turning it on and off

    private func start(asking: Bool) {
        guard VolumeKeyTap.isAllowed else {
            model.monitorVolumeNeedsAccess = true
            Log.info("Monitor volume: waiting for Accessibility permission")
            if asking { VolumeKeyTap.askForPermission() }
            watchForAccess()
            return
        }
        model.monitorVolumeNeedsAccess = false
        stopWatchingForAccess()
        if keys.start() { lookUpMonitor() }
    }

    private func stop() {
        keys.stop()
        stopWatchingForAccess()
        model.monitorVolumeNeedsAccess = false
        monitor = nil
        lookingUp = nil
    }

    /// macOS announces changes to the Accessibility list; whether this app is allowed can lag a
    /// moment behind the announcement.
    private func watchForAccess() {
        guard accessObserver == nil else { return }
        accessObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                self?.recheckAccess()
            }
        }
    }

    private func stopWatchingForAccess() {
        if let accessObserver { DistributedNotificationCenter.default().removeObserver(accessObserver) }
        accessObserver = nil
    }

    // MARK: Finding the monitor

    /// If the sound now goes to a display that macOS can't set the volume of, finds that display's
    /// DDC channel and reads its volume, off the main thread.
    private func lookUpMonitor() {
        guard let device = AudioHAL.defaultOutputDevice(),
              let uid = AudioHAL.readString(device, kAudioDevicePropertyDeviceUID) else { return }
        let overDisplayCable = AudioHAL.isDisplayOutput(device)
        guard overDisplayCable || DisplayAudio.displayIDs(fromOutputUID: uid) != nil else { return }
        let name = AudioHAL.readString(device, kAudioObjectPropertyName) ?? uid
        guard !AudioHAL.hasOutputVolume(device) else {
            Log.info("Monitor volume: \(name) has its own volume control in macOS, so the keys stay with macOS")
            return
        }
        lookingUp = uid
        Log.info("Monitor volume: sound goes to \(name); looking for its cable")
        MonitorDDC.queue.async { [weak self] in
            let displays = MonitorDDC.externalDisplays()
            let ids = DisplayAudio.displayIDs(fromOutputUID: uid)
            // By the IDs in the output's UID; else, over a display cable, the only external display.
            let monitor = displays.first { ids != nil && $0.vendorID == ids?.vendor && $0.productID == ids?.product }
                ?? (overDisplayCable && displays.count == 1 ? displays.first : nil)
            let current = monitor?.read(DDC.volume)
            let found = displays.map(\.description)
            Task { @MainActor [weak self] in self?.found(monitor, current, for: uid, among: found) }
        }
    }

    private func found(_ monitor: MonitorDDC?, _ current: (current: UInt16, max: UInt16)?, for uid: String, among displays: [String]) {
        guard lookingUp == uid else { return }
        lookingUp = nil
        guard let monitor else {
            Log.error("Monitor volume: couldn't match \(uid) to a display (external displays: \(displays.isEmpty ? "none" : displays.joined(separator: "; ")))")
            return
        }
        self.monitor = monitor
        hud.locateSoundIcon()
        if let current {
            maxValue = current.max
            volume = MonitorVolume(level: Double(min(current.current, current.max)) / Double(current.max))
            Log.info("Monitor volume: \(monitor.description) is at \(current.current) of \(current.max)")
        } else {
            Log.error("Monitor volume: \(monitor.description) didn't answer with its volume; starting from \(volume.ddcValue(max: maxValue)) of \(maxValue)")
        }
    }

    // MARK: The keys

    private func handle(_ press: VolumeKeyTap.Press) -> Bool {
        guard monitor != nil || lookingUp != nil else { return false }
        let modifiers = press.modifiers
        // ⌥ with a volume key opens Sound settings, as usual.
        if modifiers.contains(.option) && !modifiers.contains(.shift) { return false }
        // Still finding the monitor: a key pressed in that moment does nothing rather than reach macOS.
        guard monitor != nil else { return true }

        guard press.isDown else {
            // macOS plays its feedback sound when the key comes back up.
            if press.key != .mute && playsFeedback(modifiers) {
                NSSound(contentsOfFile: Self.feedbackSound, byReference: true)?.play()
            }
            return true
        }
        if press.key == .mute && press.isRepeat { return true }
        // ⇧⌥: the monitor's own smallest step (often 1 of 100), like macOS's quarter steps.
        let fine = modifiers.contains(.shift) && modifiers.contains(.option)
        volume = volume.pressing(press.key, steps: fine ? Double(maxValue) : MonitorVolume.steps)
        hud.show(volume)
        send(volume.ddcValue(max: maxValue))
        return true
    }

    /// Sound settings' "Play feedback when volume is changed"; holding ⇧ does the opposite.
    private func playsFeedback(_ modifiers: NSEvent.ModifierFlags) -> Bool {
        let on = UserDefaults.standard.integer(forKey: "com.apple.sound.beep.feedback") == 1
        let shiftOnly = modifiers.contains(.shift) && !modifiers.contains(.option)
        return on != shiftOnly
    }

    private func send(_ value: UInt16) {
        pendingValue = value
        guard !isWriting, let monitor else { return }
        isWriting = true
        writeNext(to: monitor)
    }

    private func writeNext(to monitor: MonitorDDC) {
        guard let value = pendingValue else {
            isWriting = false
            return
        }
        pendingValue = nil
        MonitorDDC.queue.async { [weak self] in
            let sent = monitor.write(DDC.volume, value)
            Task { @MainActor [weak self] in
                guard let self else { return }
                Log.debug("Monitor volume: \(value) of \(self.maxValue)\(sent ? "" : " not sent")")
                guard self.monitor === monitor else {
                    // The sound moved to another output meanwhile.
                    self.isWriting = false
                    if self.monitor != nil, let next = self.pendingValue { self.send(next) }
                    return
                }
                if !sent {
                    // Its connection may have been rebuilt, after sleep for example: find it again.
                    Log.error("Monitor volume: \(monitor.description) didn't take the volume; looking for it again")
                    self.pendingValue = nil
                    self.isWriting = false
                    self.monitor = nil
                    self.lookUpMonitor()
                    return
                }
                self.writeNext(to: monitor)
            }
        }
    }
}
