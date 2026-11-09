import CoreAudio
import Testing
@testable import TallyMic

@Suite("Panel device list")
struct DeviceListTests {
    private let headset = InputDevice(objectID: 99, uid: "headset", name: "Wireless Headset Receiver",
                                      transport: .usb, transportCode: 0)
    private let webcam = InputDevice(objectID: 115, uid: "webcam", name: "USB Webcam", transport: .usb, transportCode: 0)
    private let teams = InputDevice(objectID: 77, uid: "teams", name: "Microsoft Teams Audio", transport: .virtual, transportCode: 0)

    @Test func leavesOutHiddenInputs() {
        let known = [KnownDevice(uid: "teams", name: "Microsoft Teams Audio", transport: "virtual", visible: false)]
        let shown = DeviceList.shown(inputs: [headset, webcam, teams], known: known, currentID: 115, order: [])
        #expect(shown.map(\.id) == ["webcam", "headset"])  // by name: "USB Webcam" first
    }

    @Test func showsAHiddenInputWhileItsInUse() {
        let known = [KnownDevice(uid: "teams", name: "Microsoft Teams Audio", transport: "virtual", visible: false)]
        let shown = DeviceList.shown(inputs: [headset, webcam, teams], known: known, currentID: 77, order: [])
        #expect(shown.map(\.id).contains("teams"))
    }

    @Test func usesTheNamesGivenInTheDevicesTab() {
        let known = [KnownDevice(uid: "headset", name: headset.name, transport: "usb", displayName: "My Headset")]
        let shown = DeviceList.shown(inputs: [headset, webcam], known: known, currentID: nil, order: ["headset", "webcam"])
        #expect(shown.map(\.name) == ["My Headset", "USB Webcam"])
    }

    /// Asked for by Marcus: the panel lists inputs in the active setup's order, not by name.
    @Test func followsTheActiveSetupsOrder() {
        let known = [headset, webcam, teams].map { KnownDevice(uid: $0.uid, name: $0.name, transport: $0.transport.rawValue) }
        let desk = DeviceList.shown(inputs: [headset, webcam, teams], known: known, currentID: nil, order: ["teams", "headset", "webcam"])
        #expect(desk.map(\.id) == ["teams", "headset", "webcam"])
        let laptop = DeviceList.shown(inputs: [headset, webcam, teams], known: known, currentID: nil, order: ["webcam", "teams", "headset"])
        #expect(laptop.map(\.id) == ["webcam", "teams", "headset"])
    }

    @Test func inputsOutsideTheOrderComeLastByName() {
        let zed = InputDevice(objectID: 200, uid: "zed", name: "Zed Mic", transport: .usb, transportCode: 0)
        let alpha = InputDevice(objectID: 201, uid: "alpha", name: "Alpha Mic", transport: .usb, transportCode: 0)
        let shown = DeviceList.shown(inputs: [zed, webcam, alpha], known: [], currentID: nil, order: ["webcam"])
        #expect(shown.map(\.id) == ["webcam", "alpha", "zed"])
    }

    @Test func showsInputsItHasntRecordedYet() {
        #expect(DeviceList.shown(inputs: [webcam], known: [], currentID: nil, order: []).map(\.id) == ["webcam"])
    }
}
