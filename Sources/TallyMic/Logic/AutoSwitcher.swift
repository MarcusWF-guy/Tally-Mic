import Foundation

/// Automatic switching (SPEC 6.2), as pure logic with the time passed in, so every rule can be
/// tested without devices. AutoSwitchController feeds it events and acts on its answers.
struct AutoSwitcher: Sendable {
    /// SPEC 6.2: Tally Mic's own switch arrives as an input change within this long.
    static let ownSwitchWindow: TimeInterval = 1
    /// SPEC 6.2: an input change this soon after a device or display came or went is macOS's doing.
    static let macOSWindow: TimeInterval = 2
    /// SPEC 6.2: wait until nothing has happened for this long, then decide once.
    static let settleTime: TimeInterval = 1.5

    private var expectedSwitch: (uid: String, at: Date)?
    private var lastTopologyChange = Date.distantPast
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

    /// Anything else that calls for deciding again: the sound output, settings edited, switching
    /// turned on.
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
        /// macOS switched by itself because something connected or disconnected. Undo it.
        case macOS
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
        if time.timeIntervalSince(lastTopologyChange) < Self.macOSWindow {
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
