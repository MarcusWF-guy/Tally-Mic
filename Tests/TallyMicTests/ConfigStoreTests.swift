import Foundation
import Testing
@testable import TallyMic

@Suite("Config file")
@MainActor
struct ConfigStoreTests {
    private let folder: URL
    private let url: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("tally-mic-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appendingPathComponent("config.json")
    }

    private func contents() throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
    }

    private func device(_ name: String, uid: String, transport: Transport = .usb) -> InputDevice {
        InputDevice(objectID: 1, uid: uid, name: name, transport: transport, transportCode: 0)
    }

    @Test func recordsDevicesInTheOrderFirstSeen() throws {
        let store = ConfigStore(url: url)
        #expect(store.recordSeen([device("USB Webcam", uid: "webcam")]))
        #expect(store.recordSeen([device("Headset", uid: "headset"), device("USB Webcam", uid: "webcam")]))
        #expect(!store.recordSeen([device("USB Webcam", uid: "webcam")]))
        try store.save()

        #expect(ConfigStore(url: url).devices.map(\.uid) == ["webcam", "headset"])
        let first = (try contents()["devices"] as? [[String: Any]])?.first
        #expect(first?["name"] as? String == "USB Webcam")
        #expect(first?["transport"] as? String == "usb")
        #expect(first?["visible"] as? Bool == true)
        #expect(first?["displayName"] is NSNull)
    }

    @Test func updatesARenamedDevice() {
        let store = ConfigStore(url: url)
        store.recordSeen([device("USB Mic", uid: "mic")])
        #expect(store.recordSeen([device("USB Microphone", uid: "mic")]))
        #expect(store.devices == [KnownDevice(uid: "mic", name: "USB Microphone", transport: "usb")])
    }

    /// SPEC 7.1: a USB device without a serial number gets a new UID on another port.
    @Test func followsADeviceToANewUSBPort() {
        let store = ConfigStore(url: url)
        store.recordSeen([device("USB Microphone", uid: "port-1"), device("USB Webcam", uid: "webcam")])
        #expect(store.recordSeen([device("USB Microphone", uid: "port-2"), device("USB Webcam", uid: "webcam")]))
        #expect(store.devices.map(\.uid) == ["port-2", "webcam"])
    }

    @Test func keepsTwoIdenticalDevicesApart() {
        let store = ConfigStore(url: url)
        store.recordSeen([device("USB Microphone", uid: "port-1")])
        store.recordSeen([device("USB Microphone", uid: "port-1"), device("USB Microphone", uid: "port-2")])
        #expect(store.devices.map(\.uid) == ["port-1", "port-2"])
    }

    @Test func doesNotMatchADifferentTransport() {
        let store = ConfigStore(url: url)
        store.recordSeen([device("Headset", uid: "usb-headset", transport: .usb)])
        store.recordSeen([device("Headset", uid: "bt-headset", transport: .bluetooth)])
        #expect(store.devices.map(\.uid) == ["usb-headset", "bt-headset"])
    }

    @Test func hidesNamesAndForgetsDevices() throws {
        let store = ConfigStore(url: url)
        store.recordSeen([device("Wireless Headset Receiver", uid: "headset"),
                          device("Microsoft Teams Audio", uid: "teams", transport: .virtual),
                          device("USB Microphone", uid: "usbMic")])
        store.setVisible(false, uid: "teams")
        store.setDisplayName("  Headset ", uid: "headset")
        store.forget(uid: "usbMic")
        try store.save()

        let devices = ConfigStore(url: url).devices
        #expect(devices.map(\.uid) == ["headset", "teams"])
        #expect(devices[0].displayName == "Headset")
        #expect(devices[0].shownName == "Headset")
        #expect(devices[1].visible == false)
        #expect(devices[1].shownName == "Microsoft Teams Audio")
    }

    @Test func blankNameGoesBackToTheRealName() throws {
        let store = ConfigStore(url: url)
        store.recordSeen([device("HS50 Headset", uid: "headset")])
        store.setDisplayName("Headset", uid: "headset")
        store.setDisplayName("   ", uid: "headset")
        try store.save()
        #expect(ConfigStore(url: url).devices.first?.displayName == nil)
        let first = (try contents()["devices"] as? [[String: Any]])?.first
        #expect(first?["displayName"] is NSNull)
    }

    @Test func aForgottenDeviceComesBackAsNew() {
        let store = ConfigStore(url: url)
        store.recordSeen([device("USB Mic", uid: "mic")])
        store.setVisible(false, uid: "mic")
        store.forget(uid: "mic")
        store.recordSeen([device("USB Mic", uid: "mic")])
        #expect(store.devices == [KnownDevice(uid: "mic", name: "USB Mic", transport: "usb")])
    }

    @Test func startsWithOneLaptopSetup() {
        #expect(ConfigStore(url: url).setups == [Setup.firstRun])
    }

    @Test func savesSetupsAndDisplays() throws {
        let deskMonitor = DisplayID(name: "Desk Monitor", vendorID: 1234, modelID: 5678, serial: 4321)
        let store = ConfigStore(url: url)
        store.setSetups([Setup(id: "desk", name: "Desk", trigger: deskMonitor, order: ["headset", "usbMic"]), Setup.firstRun])
        #expect(store.recordDisplays([deskMonitor]))
        #expect(!store.recordDisplays([deskMonitor]))
        try store.save()

        let reloaded = ConfigStore(url: url)
        #expect(reloaded.setups.map(\.id) == ["desk", "laptop"])
        #expect(reloaded.setups[0].trigger == deskMonitor)
        #expect(reloaded.setups[0].order == ["headset", "usbMic"])
        #expect(reloaded.displays == [deskMonitor])
        let trigger = (try contents()["setups"] as? [[String: Any]])?.first?["trigger"] as? [String: Any]
        #expect(trigger?["type"] as? String == "display")
        #expect(trigger?["vendorId"] as? Int == 1234)
    }

    @Test func keepsUnknownKeysInSetups() throws {
        try Data("""
            {"version": 1, "setups": [{"id": "laptop", "name": "Laptop", "trigger": null, "order": [], "futureKey": 3}]}
            """.utf8).write(to: url)
        let store = ConfigStore(url: url)
        var setups = store.setups
        setups[0].name = "On the Go"
        store.setSetups(setups)
        try store.save()
        let saved = (try contents()["setups"] as? [[String: Any]])?.first
        #expect(saved?["name"] as? String == "On the Go")
        #expect(saved?["futureKey"] as? Int == 3)
    }

    @Test func remembersLaunchAtLogin() throws {
        let store = ConfigStore(url: url)
        #expect(store.launchAtLogin == nil)
        store.launchAtLogin = true
        try store.save()
        #expect(ConfigStore(url: url).launchAtLogin == true)
        #expect((try contents()["general"] as? [String: Any])?["launchAtLogin"] as? Bool == true)
    }

    @Test func keepsKeysItDoesNotKnow() throws {
        let original = """
            {"version": 1, "preferredOrderEnabled": true, "setups": [{"id": "desk"}],
             "devices": [{"uid": "webcam", "name": "USB Webcam", "transport": "usb",
                          "displayName": "Brio", "visible": false, "futureKey": 7}]}
            """
        try Data(original.utf8).write(to: url)

        let store = ConfigStore(url: url)
        store.recordSeen([device("USB Webcam 4K", uid: "webcam")])
        try store.save()

        let json = try contents()
        #expect(json["preferredOrderEnabled"] as? Bool == true)
        #expect((json["setups"] as? [[String: Any]])?.first?["id"] as? String == "desk")
        let webcam = (json["devices"] as? [[String: Any]])?.first
        #expect(webcam?["name"] as? String == "USB Webcam 4K")
        #expect(webcam?["displayName"] as? String == "Brio")
        #expect(webcam?["visible"] as? Bool == false)
        #expect(webcam?["futureKey"] as? Int == 7)
    }

    @Test func setsAnUnreadableFileAside() throws {
        try Data("{ not json".utf8).write(to: url)
        let store = ConfigStore(url: url)
        #expect(store.devices.isEmpty)

        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(files.contains { $0.hasPrefix("config.unreadable-") })
    }
}
