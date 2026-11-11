import Foundation
import Testing
@testable import TallyMic

/// SPEC 6.2's list: docking, undocking, connect, disconnect, lid close while docked, hidden device,
/// macOS auto-switch vs manual change (which turns switching off), Tally Mic's own switch not
/// counting as a manual change, event bursts, and a headset only while it's the sound output.
@Suite("Automatic switching")
struct AutoSwitcherTests {
    private let headset = InputDevice(objectID: 1, uid: "headset-mic", name: "Wireless Headset Receiver",
                                      transport: .usb, transportCode: 0, outputUIDs: ["headset-out"])
    private let usbMic = InputDevice(objectID: 2, uid: "usbMic", name: "USB Microphone", transport: .usb, transportCode: 0)
    private let builtIn = InputDevice(objectID: 3, uid: "builtin", name: "MacBook Pro Microphone", transport: .builtIn,
                                      transportCode: 0, outputUIDs: ["speakers"])
    private let webcam = InputDevice(objectID: 4, uid: "webcam", name: "USB Webcam", transport: .usb, transportCode: 0)
    private let airpods = InputDevice(objectID: 5, uid: "airpods", name: "User's AirPods Pro", transport: .bluetooth,
                                      transportCode: 0, outputUIDs: ["airpods"])
    private let teams = InputDevice(objectID: 6, uid: "teams", name: "Microsoft Teams Audio", transport: .virtual,
                                    transportCode: 0, outputUIDs: ["teams"])

    private let deskMonitor = DisplayID(name: "Desk Monitor", vendorID: 1234, modelID: 5678, serial: 4321)
    private var desk: Setup { Setup(id: "desk", name: "Desk", trigger: deskMonitor, order: ["headset-mic", "usbMic", "builtin", "webcam"]) }
    private let laptop = Setup(id: "laptop", name: "Laptop", trigger: nil, order: ["airpods", "headset-mic", "builtin"])

    private var known: [KnownDevice] {
        [headset, usbMic, builtIn, webcam, airpods, teams].map { KnownDevice(uid: $0.uid, name: $0.name, transport: $0.transport.rawValue) }
    }

    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    /// The sound output defaults to the headset's headphones, as at a desk.
    private func decide(_ setup: Setup, _ connected: [InputDevice], current: InputDevice?, lidClosed: Bool = false,
                        output: String? = "headset-out", known: [KnownDevice]? = nil) -> AutoSwitcher.Decision {
        AutoSwitcher.decide(setup: setup, known: known ?? self.known, connected: connected, lidClosed: lidClosed,
                            outputUID: output, currentUID: current?.uid)
    }

    @Test func dockingSwitchesToTheDesksFirstChoice() {
        #expect(decide(laptop, [builtIn], current: builtIn, output: "speakers") == .stay)
        #expect(decide(desk, [headset, usbMic, builtIn, webcam], current: builtIn) == .switchTo(headset))
    }

    @Test func undockingFallsBackToTheLaptopOrder() {
        #expect(decide(laptop, [builtIn], current: usbMic, output: "speakers") == .switchTo(builtIn))
    }

    @Test func aPreferredDeviceConnecting() {
        #expect(decide(desk, [usbMic, builtIn], current: usbMic) == .stay)
        #expect(decide(desk, [headset, usbMic, builtIn], current: usbMic) == .switchTo(headset))
    }

    @Test func theCurrentDeviceDisconnecting() {
        #expect(decide(desk, [usbMic, builtIn], current: nil) == .switchTo(usbMic))
    }

    @Test func lidClosedWhileDockedSkipsTheMacBookMic() {
        #expect(decide(desk, [builtIn, webcam], current: builtIn, lidClosed: true) == .switchTo(webcam))
        #expect(decide(laptop, [builtIn], current: nil, lidClosed: true) == .stay)
    }

    @Test func hiddenDevicesAreNeverPicked() {
        var known = self.known
        known[0].visible = false  // the headset
        #expect(decide(desk, [headset, usbMic], current: nil, known: known) == .switchTo(usbMic))
    }

    /// SPEC 6.2: a wireless headset's receiver stays plugged in with the headset off, and macOS can't tell.
    /// Its mic is only used while its headphones are the sound output.
    @Test func aHeadsetOnlyWhileItsTheSoundOutput() {
        #expect(decide(desk, [headset, usbMic, builtIn], current: headset, output: "deskMonitor-speakers") == .switchTo(usbMic))
        #expect(decide(desk, [headset, usbMic, builtIn], current: usbMic, output: "headset-out") == .switchTo(headset))
        #expect(decide(desk, [headset, usbMic], current: usbMic, output: nil) == .stay)
        // AirPods first in Laptop's order: only while they're what you're listening to.
        #expect(decide(laptop, [airpods, builtIn], current: builtIn, output: "speakers") == .stay)
        #expect(decide(laptop, [airpods, builtIn], current: builtIn, output: "airpods") == .switchTo(airpods))
    }

    /// The MacBook mic and USB mics aren't headsets: the sound output doesn't matter for them, even
    /// though the MacBook mic has speakers of its own.
    @Test func otherMicsIgnoreTheSoundOutput() {
        #expect(!builtIn.isHeadset)
        #expect(!usbMic.isHeadset)
        #expect(headset.isHeadset && airpods.isHeadset)
        #expect(decide(laptop, [builtIn], current: nil, output: "deskMonitor-speakers") == .switchTo(builtIn))
    }

    /// AirPods connect and macOS makes them the input: undo it. The same change later is a choice,
    /// which turns automatic switching off.
    @Test func macOSSwitchingVersusAManualChange() {
        var switcher = AutoSwitcher()
        switcher.topologyChanged(at: at(0))
        #expect(switcher.inputChanged(to: "airpods", at: at(0.8)) == .macOS)
        #expect(switcher.inputChanged(to: "airpods", at: at(30)) == .manual)
    }

    /// Docking: macOS switched to a webcam as it connected, Tally Mic switched back, and macOS
    /// switched to the webcam again 3 seconds after it connected. Still macOS.
    @Test func macOSSwitchingAgainAFewSecondsLater() {
        var switcher = AutoSwitcher()
        switcher.topologyChanged(at: at(0))
        #expect(switcher.inputChanged(to: "webcam", at: at(0)) == .macOS)
        switcher.willSwitch(to: "usbMic", at: at(2))
        #expect(switcher.inputChanged(to: "usbMic", at: at(2.1)) == .own)
        #expect(switcher.inputChanged(to: "webcam", at: at(3)) == .macOS)
    }

    /// The monitor sleeps, its speakers go away, and macOS picks a new input at the same moment.
    @Test func theSoundOutputChangingIsMacOS() {
        var switcher = AutoSwitcher()
        switcher.outputChanged(at: at(100))
        #expect(switcher.inputChanged(to: "webcam", at: at(100)) == .macOS)
        #expect(switcher.inputChanged(to: "webcam", at: at(99.5)) == .macOS)
        #expect(switcher.inputChanged(to: "webcam", at: at(120)) == .manual)
    }

    /// A dictation app sets the Mac's mic to the one it uses as it starts, before or just after it
    /// shows up as using the mic. That's the app, not a choice.
    @Test func anAppSwitchingAsItStarts() {
        var switcher = AutoSwitcher()
        switcher.appsStartedRecording(["com.example.dictation"], at: at(201))
        #expect(switcher.inputChanged(to: "webcam", at: at(200)) == .app(["com.example.dictation"]))
        #expect(switcher.inputChanged(to: "webcam", at: at(202)) == .app(["com.example.dictation"]))
        #expect(switcher.inputChanged(to: "webcam", at: at(230)) == .manual)
    }

    /// System Settings' level meter uses the mic while the Sound pane is open, so a pick made there
    /// can look like an app starting. It's still a choice.
    @Test func aPickInSystemSettingsIsStillAChoice() {
        var switcher = AutoSwitcher()
        switcher.appsStartedRecording(["com.apple.Sound-Settings.extension"], at: at(300))
        #expect(switcher.inputChanged(to: "webcam", at: at(300.5)) == .manual)
    }

    /// When a device connects, macOS can announce the new input before the device list changes.
    /// The controller sorts the change a moment later, so the device news counts.
    @Test func aDeviceChangeJustAfterTheInputChangeStillCountsAsMacOS() {
        var switcher = AutoSwitcher()
        switcher.topologyChanged(at: at(0.2))
        #expect(switcher.inputChanged(to: "airpods", at: at(0)) == .macOS)
    }

    @Test func itsOwnSwitchIsntAManualChange() {
        var switcher = AutoSwitcher()
        switcher.willSwitch(to: "headset-mic", at: at(50))
        #expect(switcher.inputChanged(to: "headset-mic", at: at(50.3)) == .own)
        // A late answer isn't its own switch.
        switcher.willSwitch(to: "headset-mic", at: at(60))
        #expect(switcher.inputChanged(to: "headset-mic", at: at(61.5)) == .manual)
    }

    /// Docking fires a burst of events: decide only once things have been quiet for 1.5 seconds.
    @Test func waitsForABurstToSettle() {
        var switcher = AutoSwitcher()
        for time in [0, 0.3, 0.7, 1.1] { switcher.topologyChanged(at: at(time)) }
        #expect(!switcher.isSettled(at: at(2.0)))
        #expect(switcher.isSettled(at: at(2.6)))
        switcher.somethingChanged(at: at(2.2))
        #expect(!switcher.isSettled(at: at(3.0)))
        #expect(switcher.isSettled(at: at(3.7)))
    }

    @Test func noConnectedChoiceMeansStay() {
        #expect(decide(desk, [teams], current: teams) == .stay)
    }
}
