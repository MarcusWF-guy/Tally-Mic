import CoreAudio
import Foundation

/// Keeps AppModel in step with Core Audio and makes the changes the panel asks for (SPEC 7).
/// Event-driven: property listeners, no polling (SPEC 7.4).
@MainActor
final class AudioSystem {
    private let model: AppModel
    private let config: ConfigStore

    /// An input connected or disconnected (SPEC 6.2), for automatic switching.
    var onTopologyChange: (() -> Void)?
    /// The system input changed, by anyone: the UID of the new one, or nil if there's none.
    var onInputChange: ((String?) -> Void)?
    /// The sound output changed. A headset's mic follows its headphones (SPEC 6.2), and the volume
    /// keys follow a monitor (SPEC 7.7).
    var onOutputChange: [() -> Void] = []

    private var systemListeners: [PropertyListener] = []
    /// Per input: its name, and whether any app is using it.
    private var deviceListeners: [PropertyListener] = []
    private var volumeListeners: [PropertyListener] = []
    /// The current input's mute switch, so a mute made elsewhere shows in Tally Mic.
    private var muteListener: PropertyListener?
    /// Volumes from before muting inputs that have no mute switch, to put back on unmute.
    private var volumesBeforeMute: [String: Float] = [:]
    /// At launch the mute state is read from the input rather than applied to it.
    private var muteStateRead = false
    /// One per app Core Audio knows about, for whether it's recording (SPEC 5.1).
    private var processListeners: [PropertyListener] = []
    private var volumeControl: VolumeControl = .none

    /// SPEC 7.3: writes while dragging are coalesced to one every 30 ms.
    private static let volumeWriteInterval: Duration = .milliseconds(30)
    private var pendingVolume: Float?
    private var volumeWriteScheduled = false
    /// The device answers each write with a volume notification, often rounded to its own steps.
    /// Ignoring those for a moment after a local change keeps the slider from jittering under
    /// the pointer.
    private var lastLocalVolumeChange = ContinuousClock.now - .seconds(60)
    private static let localChangeQuiet: Duration = .milliseconds(300)

    init(model: AppModel, config: ConfigStore) {
        self.model = model
        self.config = config

        let devices = PropertyListener.add(AudioHAL.system, AudioHAL.address(kAudioHardwarePropertyDevices)) {
            [weak self] in self?.devicesChanged()
        }
        let defaultInput = PropertyListener.add(
            AudioHAL.system, AudioHAL.address(kAudioHardwarePropertyDefaultInputDevice)
        ) { [weak self] in self?.currentInputChanged() }
        let processes = PropertyListener.add(
            AudioHAL.system, AudioHAL.address(kAudioHardwarePropertyProcessObjectList)
        ) { [weak self] in self?.processesChanged() }
        let defaultOutput = PropertyListener.add(
            AudioHAL.system, AudioHAL.address(kAudioHardwarePropertyDefaultOutputDevice)
        ) { [weak self] in self?.outputChanged() }
        systemListeners = [devices, defaultInput, processes, defaultOutput].compactMap { $0 }

        model.outputUID = AudioHAL.defaultOutputUID()
        devicesChanged()
        processesChanged()
    }

    // MARK: Recording apps

    /// Apps start and quit, so the per-app listeners are rebuilt whenever the list changes.
    ///
    /// macOS 27.2 never sends a notification when an app's "recording" property changes, only when
    /// it's read (found with Voice Memos in Milestone 1). So Tally Mic listens for the changes that
    /// are announced, an app starting or stopping audio of any kind (here) and an input device
    /// starting or stopping (`devicesChanged`), and reads which apps are recording each time.
    private func processesChanged() {
        processListeners.forEach { $0.remove() }
        processListeners = AudioHAL.processIDs().compactMap { process in
            PropertyListener.add(process, MicUsage.runningAnything) { [weak self] in self?.recordingChanged() }
        }
        recordingChanged()
    }

    private func recordingChanged() {
        let apps = MicUsage.recordingApps()
        guard apps != model.recordingApps else { return }
        if apps.isEmpty {
            Log.info("Microphone no longer in use")
        } else {
            Log.info("Microphone in use by \(apps.joined(separator: ", "))")
        }
        model.recordingApps = apps
    }

    // MARK: Changes from the panel

    /// SPEC 7.2: makes `device` the system input, then reads it back to check it stuck.
    /// `reason` goes in the log: "Panel" or "Auto".
    func select(_ device: InputDevice, reason: String) {
        guard device.objectID != model.currentInputID else { return }
        Log.info("\(reason): switching input to \(device.name)")
        let status = AudioHAL.write(
            AudioHAL.system, AudioHAL.address(kAudioHardwarePropertyDefaultInputDevice), device.objectID)
        let now = AudioHAL.defaultInputDevice()
        if status != noErr || now != device.objectID {
            let current = model.inputs.first { $0.objectID == now }?.name ?? "none"
            Log.error("Switching to \(device.name) didn't stick (status \(status)). The input is still \(current).")
        }
        // The listener reports the change too; updating now makes the panel respond at once.
        currentInputChanged()
    }

    // MARK: Mute (SPEC 7.5)

    /// Universal mute: whichever input is current is muted, and stays so when the input changes.
    /// Returns false if the current input can't be muted.
    @discardableResult
    func setMuted(_ muted: Bool) -> Bool {
        guard muted != model.isMuted else { return model.canMuteCurrent || !muted }
        model.isMuted = muted
        Log.info("Microphone \(muted ? "muted" : "unmuted")")
        return applyMute()
    }

    /// Makes the current input match `model.isMuted`.
    @discardableResult
    private func applyMute() -> Bool {
        guard let id = model.currentInputID, let uid = model.currentInput?.uid ?? AudioHAL.readString(id, kAudioDevicePropertyDeviceUID)
        else { return !model.isMuted }
        switch MuteControl.find(for: id) {
        case .mute:
            if MuteControl.mute.isMuted(id) != model.isMuted {
                let status = AudioHAL.write(id, MuteControl.address, UInt32(model.isMuted ? 1 : 0))
                if status != noErr { Log.error("Couldn't \(model.isMuted ? "mute" : "unmute") the input (status \(status))") }
            }
            return true
        case .volume(let control):
            if model.isMuted {
                if volumesBeforeMute[uid] == nil { volumesBeforeMute[uid] = control.read(from: id) }
                control.write(0, to: id)
            } else if let volume = volumesBeforeMute.removeValue(forKey: uid) {
                control.write(volume, to: id)
            }
            refreshVolume()
            return true
        case .none:
            if model.isMuted { Log.error("The current input can't be muted: it has no mute or volume control") }
            return !model.isMuted
        }
    }

    private func muteChangedElsewhere() {
        guard let id = model.currentInputID, let muted = MuteControl.mute.isMuted(id), muted != model.isMuted else { return }
        Log.info("Microphone \(muted ? "muted" : "unmuted") outside Tally Mic")
        model.isMuted = muted
    }

    func setVolume(_ value: Float) {
        guard volumeControl != .none else { return }
        model.volume = value
        pendingVolume = value
        lastLocalVolumeChange = .now
        guard !volumeWriteScheduled else { return }
        volumeWriteScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.volumeWriteInterval)
            self?.writePendingVolume()
        }
    }

    private func writePendingVolume() {
        volumeWriteScheduled = false
        guard let value = pendingVolume, let device = model.currentInputID else { return }
        pendingVolume = nil
        volumeControl.write(value, to: device)
    }

    // MARK: Changes from Core Audio

    private func devicesChanged() {
        let old = model.inputs
        let fresh = InputDevice.readAll()

        for device in fresh where !old.contains(where: { $0.uid == device.uid }) {
            let volume = VolumeControl.find(for: device.objectID).summary
            Log.info("Input connected: \(device.name) (\(device.transport.rawValue), volume \(volume), UID \(device.uid))")
        }
        for device in old where !fresh.contains(where: { $0.uid == device.uid }) {
            Log.info("Input disconnected: \(device.name)")
        }
        for device in fresh {
            if let before = old.first(where: { $0.uid == device.uid }), before.name != device.name {
                Log.info("Input renamed: \(before.name) is now \(device.name)")
            }
        }

        let topologyChanged = Set(old.map(\.uid)) != Set(fresh.map(\.uid))
        model.inputs = fresh
        if config.recordSeen(fresh) { config.saveOrLog() }
        model.knownDevices = config.devices
        if topologyChanged { onTopologyChange?() }

        deviceListeners.forEach { $0.remove() }
        deviceListeners = fresh.flatMap { device in
            [
                PropertyListener.add(device.objectID, AudioHAL.address(kAudioObjectPropertyName)) {
                    [weak self] in self?.devicesChanged()
                },
                // An input starting or stopping is the other announced sign of recording (see
                // `processesChanged`).
                PropertyListener.add(device.objectID, MicUsage.deviceRunning) { [weak self] in self?.recordingChanged() },
            ].compactMap { $0 }
        }
        currentInputChanged()
    }

    private func currentInputChanged() {
        let id = AudioHAL.defaultInputDevice()
        let control = id.map(VolumeControl.find) ?? .none
        guard id != model.currentInputID || control != volumeControl else {
            volumeChangedElsewhere()
            return
        }

        let changed = id != model.currentInputID
        if changed {
            // When macOS switches to a device that was just plugged in, this can arrive before
            // the device list changes, so ask Core Audio for the name if the list doesn't have it.
            let known = model.inputs.first { $0.objectID == id }
            let name = known?.name ?? id.flatMap { AudioHAL.readString($0, kAudioObjectPropertyName) } ?? "none"
            Log.info("Input is now \(name)")
            // A device Tally Mic hasn't listed yet means the device list is about to change too.
            if known == nil, id != nil { onTopologyChange?() }
        }
        model.currentInputID = id
        volumeControl = control
        pendingVolume = nil

        volumeListeners.forEach { $0.remove() }
        volumeListeners = []
        if let id {
            volumeListeners = control.elements.compactMap { element in
                PropertyListener.add(id, VolumeControl.address(element)) { [weak self] in
                    self?.volumeChangedElsewhere()
                }
            }
        }
        model.volume = id.flatMap { control.read(from: $0) }
        if changed {
            let mute = id.map(MuteControl.find) ?? .none
            model.canMuteCurrent = mute != .none
            muteListener?.remove()
            muteListener = id.flatMap { id in
                mute == .mute ? PropertyListener.add(id, MuteControl.address) { [weak self] in self?.muteChangedElsewhere() } : nil
            }
            if muteStateRead {
                applyMute()
            } else if let id {
                // At launch, take the state from the input rather than unmuting it.
                model.isMuted = mute.isMuted(id) ?? false
                muteStateRead = true
            }
        }
        if changed {
            onInputChange?(id.flatMap { id in
                model.inputs.first { $0.objectID == id }?.uid ?? AudioHAL.readString(id, kAudioDevicePropertyDeviceUID)
            })
        }
    }

    private func outputChanged() {
        let uid = AudioHAL.defaultOutputUID()
        guard uid != model.outputUID else { return }
        model.outputUID = uid
        Log.info("Sound output is now \(uid ?? "none")")
        onOutputChange.forEach { $0() }
    }

    private func volumeChangedElsewhere() {
        guard ContinuousClock.now - lastLocalVolumeChange > Self.localChangeQuiet else { return }
        refreshVolume()
    }

    private func refreshVolume() {
        model.volume = model.currentInputID.flatMap { volumeControl.read(from: $0) }
    }
}
