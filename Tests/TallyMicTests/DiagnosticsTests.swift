import Foundation
import Testing
@testable import TallyMic

@Suite("Copy Diagnostics")
struct DiagnosticsTests {
    private func snapshot(config: String? = nil, logLines: [String] = []) -> Diagnostics.Snapshot {
        let headset = InputDevice(
            objectID: 99, uid: "AppleUSBAudioEngine:Unknown Manufacturer:Headset:1", name: "Wireless Headset Receiver",
            transport: .usb, transportCode: 0x7573_6220)
        let webcam = InputDevice(
            objectID: 115, uid: "AppleUSBAudioEngine:Unknown Manufacturer:USB Webcam:4", name: "USB Webcam",
            transport: .usb, transportCode: 0x7573_6220)
        let camo = InputDevice(
            objectID: 7, uid: "camo", name: "Camo Microphone", transport: .virtual, transportCode: 0x7669_7274)
        return Diagnostics.Snapshot(
            appVersion: "0.1 (7)", macOS: "Version 27.2 (Build 26B123)",
            date: Date(timeIntervalSince1970: 0), lidClosed: true, currentInputID: 115,
            devices: [
                .init(device: headset, channels: 1, volume: .channels([1]), level: 1),
                .init(device: webcam, channels: 2, volume: .main, level: 0.37),
                .init(device: camo, channels: 1, volume: .none, level: nil),
            ],
            config: config, logLines: logLines)
    }

    @Test func describesEveryInput() {
        let report = Diagnostics.report(snapshot())
        #expect(report.contains("Lid: closed"))
        #expect(report.contains("Recording now: nothing"))
        #expect(report.contains("Current input: USB Webcam"))
        #expect(report.contains("Inputs (3):"))
        #expect(report.contains("- USB Webcam [current]"))
        #expect(report.contains("Volume: settable (channel 1), now 100%"))
        #expect(report.contains("Volume: settable (main element), now 37%"))
        #expect(report.contains("Volume: not settable\n"))
        #expect(report.contains("Transport: usb ('usb '), icon headphones"))
    }

    @Test func namesTheAppsRecording() {
        var recording = snapshot()
        recording.recordingApps = ["com.example.recorder", "com.example.meetings"]
        #expect(Diagnostics.report(recording).contains("Recording now: com.example.recorder, com.example.meetings"))
    }

    @Test func includesConfigAndLog() {
        let report = Diagnostics.report(snapshot(config: "{\"version\": 1}", logLines: ["one", "two"]))
        #expect(report.contains("{\"version\": 1}"))
        #expect(report.hasSuffix("one\ntwo"))
        #expect(Diagnostics.report(snapshot()).contains("(none yet)"))
    }
}
