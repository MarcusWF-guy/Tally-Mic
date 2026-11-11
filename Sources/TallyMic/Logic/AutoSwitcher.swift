import Foundation

/// Automatic switching (SPEC 6.2), as pure logic with the time passed in, so every rule can be
/// tested without devices. AutoSwitchController feeds it events and acts on its answers.
struct AutoSwitcher: Sendable {
    /// SPEC 6.2: Tally Mic's own switch arrives as an input change within this long.
    static let ownSwitchWindow: TimeInterval = 1
    /// SPEC 6.2: an input change this soon after a device or display came or went is macOS's doing.
    /// macOS can switch again a few seconds after a device connects (3 seconds when docking, in
    /// Marcus's log), so this is generous: nobody picks a mic in System Settings that fast.
    static let macOSWindow: TimeInterval = 10
    /// SPEC 6.2: an input change this close to the sound output changing, before or after, is macOS's
    /// doing. When the monitor sleeps, its speakers go away and macOS picks a new input too.
    static let outputWindow: TimeInterval = 2
    /// SPEC 6.2: an input change this close to an app starting to use the mic, before or after, is
    /// that app's doing. Some apps, a dictation app for one, set the Mac's mic as they start.
    static let appWindow: TimeInterval = 2.5
    /// System Settings' input level meter uses the mic while the Sound pane is open. It doesn't
    /// change the input; a pick made there is a person's.
    static let notApps: Set<String> = ["com.apple.Sound-Settings.extension", "com.apple.systempreferences"]
    /// SPEC 6.2: wait until nothing has happened for this long, then decide once.
    static let settleTime: TimeInterval = 1.5

    private var expectedSwitch: (uid: String, at: Date)?
    private var lastTopologyChange = Date.distantPast
    private var lastOutputChange = Date.distantPast
    private var lastAppStart: (apps: [String], at: Date)?
    private(set) var lastEvent = Date.distantPast

    // MARK: Picking

    /// SPEC 6.2: the first input in the setup's order that's connected, not hidden, and available.
    static func preferred(_ setup: Setup, known: [KnownDevice], connected: [InputDevice], lidClosed: Bool,
                          outputUID: String?) -> InputDevice? {
        let byUID = Dictionary(connected.map { ($0.uid, $0) }, uniquingKeysWith: { first, _ in first })
        for candidate in SetupResolver.fullOrder(setup, known: known) where candidate.visible {
            guard let device = byUID[candidate.uid],
                  isAvailable(device, lidClosed: lidClosed, outputUID: outputUID) else { continue }
            return device
        }
        return nil
    }

    /// The MacBook mic isn't available with the lid closed. A headset's mic is only available while
    /// its own headphones are the sound output: its receiver can stay plugged in with the headset
    /// off, and macOS can't tell (SPEC 6.2).
    static func isAvailable(_ device: InputDevice, lidClosed: Bool, outputUID: String?) -> Bool {
        if lidClosed && device.transport == .builtIn { return false }
        if device.isHeadset && !device.outputUIDs.isEmpty {
            return outputUID.map(device.outputUIDs.contains) ?? false
        }
        return true
    }

    // MARK: Events

    /// A device or display came or went, the lid opened or closed, or the Mac woke.
    mutating func topologyChanged(at time: Date) {
        lastTopologyChange = time
        lastEvent = time
    }

    /// The sound output changed. It also calls for deciding again, for headsets (see `isAvailable`).
    mutating func outputChanged(at time: Date) {
        lastOutputChange = time
        lastEvent = time
    }

    /// Apps that weren't using the mic started to.
    mutating func appsStartedRecording(_ apps: [String], at time: Date) {
        let apps = apps.filter { !Self.notApps.contains($0) }
        guard !apps.isEmpty else { return }
        lastAppStart = (apps, time)
    }

    /// Anything else that calls for deciding again: settings edited, switching turned on, an app
    /// done with the mic.
    mutating func somethingChanged(at time: Date) {
        lastEvent = time
    }

    /// Tally Mic is about to switch to `uid`. The input change that follows isn't someone else's.
    mutating func willSwitch(to uid: String, at time: Date) {
        expectedSwitch = (uid, time)
    }

    enum InputChange: Equatable, Sendable {
        /// Tally Mic's own switch.
        case own
        /// macOS switched by itself because something connected or disconnected, or the sound
        /// output changed. Undo it.
        case macOS
        /// An app switched it as it started using the mic. Leave it to the app until it's done,
        /// then undo it (SPEC 6.2).
        case app([String])
        /// Someone picked it, in System Settings say. Automatic switching turns off (SPEC 6.2).
        case manual
    }

    /// SPEC 6.2: sorts an input change by who made it.
    mutating func inputChanged(to uid: String?, at time: Date) -> InputChange {
        lastEvent = time
        if let expected = expectedSwitch, expected.uid == uid, time.timeIntervalSince(expected.at) < Self.ownSwitchWindow {
            expectedSwitch = nil
            return .own
        }
        if let start = lastAppStart, abs(time.timeIntervalSince(start.at)) < Self.appWindow {
            return .app(start.apps)
        }
        if time.timeIntervalSince(lastTopologyChange) < Self.macOSWindow
            || abs(time.timeIntervalSince(lastOutputChange)) < Self.outputWindow {
            return .macOS
        }
        return .manual
    }

    // MARK: Deciding

    /// Whether events have stopped for long enough to decide.
    func isSettled(at time: Date) -> Bool {
        time.timeIntervalSince(lastEvent) >= Self.settleTime
    }

    enum Decision: Equatable, Sendable {
        case stay
        case switchTo(InputDevice)
    }

    /// What to do once settled: switch to the setup's first available choice if it isn't the input.
    static func decide(setup: Setup, known: [KnownDevice], connected: [InputDevice], lidClosed: Bool,
                       outputUID: String?, currentUID: String?) -> Decision {
        guard let preferred = preferred(setup, known: known, connected: connected, lidClosed: lidClosed, outputUID: outputUID),
              preferred.uid != currentUID else { return .stay }
        return .switchTo(preferred)
    }
}
