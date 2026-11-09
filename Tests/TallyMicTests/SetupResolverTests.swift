import Testing
@testable import TallyMic

@Suite("Setups")
struct SetupResolverTests {
    private let deskMonitor = DisplayID(name: "Desk Monitor", vendorID: 1234, modelID: 5678, serial: 4321)
    private let studio = DisplayID(name: "Studio Display", vendorID: 1552, modelID: 44_000, serial: 12)
    private var desk: Setup { Setup(id: "desk", name: "Desk", trigger: deskMonitor, order: ["headset", "usbMic", "builtin"]) }
    private let laptop = Setup(id: "laptop", name: "Laptop", trigger: nil, order: ["headset", "builtin"])

    @Test func dockingPicksTheDesk() {
        #expect(SetupResolver.active([desk, laptop], connected: [deskMonitor]).id == "desk")
    }

    @Test func undockingFallsBackToTheLaptop() {
        #expect(SetupResolver.active([desk, laptop], connected: []).id == "laptop")
    }

    @Test func anotherDisplayStillMeansLaptop() {
        #expect(SetupResolver.active([desk, laptop], connected: [studio]).id == "laptop")
    }

    @Test func theFirstMatchingSetupWins() {
        let studioSetup = Setup(id: "studio", name: "Studio", trigger: studio, order: [])
        #expect(SetupResolver.active([studioSetup, desk, laptop], connected: [deskMonitor, studio]).id == "studio")
        #expect(SetupResolver.active([desk, studioSetup, laptop], connected: [deskMonitor, studio]).id == "desk")
    }

    /// SPEC 6.1: a display reporting no numbers is matched by name.
    @Test func matchesByNameWhenThereAreNoNumbers() {
        let noNumbers = DisplayID(name: "Desk Monitor", vendorID: 0, modelID: 0, serial: 0)
        #expect(noNumbers.matches(deskMonitor))
        #expect(deskMonitor.matches(noNumbers))
        #expect(!DisplayID(name: "Other", vendorID: 0, modelID: 0, serial: 0).matches(deskMonitor))
    }

    @Test func aSecondMonitorOfTheSameModelIsADifferentDisplay() {
        let twin = DisplayID(name: "Desk Monitor", vendorID: 1234, modelID: 5678, serial: 999)
        #expect(!twin.matches(deskMonitor))
        #expect(SetupResolver.active([desk, laptop], connected: [twin]).id == "laptop")
    }

    @Test func alwaysHasExactlyOneFallbackAndItsLast() {
        #expect(SetupResolver.normalized([]).map(\.id) == ["laptop"])
        #expect(SetupResolver.normalized([laptop, desk]).map(\.id) == ["desk", "laptop"])
        let second = Setup(id: "spare", name: "Spare", trigger: nil, order: [])
        #expect(SetupResolver.normalized([laptop, desk, second]).map(\.id) == ["desk", "laptop"])
        #expect(SetupResolver.normalized([desk]).map(\.id) == ["desk", "laptop"])
    }

    @Test func fullOrderPutsUnlistedInputsLastInTheOrderFirstSeen() {
        let known = ["builtin", "webcam", "headset", "teams", "usbMic"].map {
            KnownDevice(uid: $0, name: $0, transport: "usb")
        }
        let order = SetupResolver.fullOrder(Setup(id: "x", name: "X", trigger: deskMonitor, order: ["headset", "gone", "usbMic", "headset"]), known: known)
        #expect(order.map(\.uid) == ["headset", "usbMic", "builtin", "webcam", "teams"])
    }

    @Test func offersUnusedConnectedDisplays() {
        #expect(SetupResolver.unusedDisplays([laptop], connected: [deskMonitor]) == [deskMonitor])
        #expect(SetupResolver.unusedDisplays([desk, laptop], connected: [deskMonitor, studio]) == [studio])
    }
}
