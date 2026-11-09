import AppKit
import CoreAudio
import Testing
@testable import TallyMic

@Suite("Device icons")
struct DeviceIconTests {
    /// A typical desk: a headset, a webcam, a USB mic, the MacBook's own, and a virtual device.
    @Test(arguments: [
        ("Wireless Headset Receiver", Transport.usb, "headphones"),
        ("USB Webcam", .usb, "web.camera"),
        ("USB Microphone", .usb, "mic"),
        ("MacBook Pro Microphone", .builtIn, "laptopcomputer"),
        ("Microsoft Teams Audio", .virtual, "waveform"),
    ])
    func typicalInputs(name: String, transport: Transport, symbol: String) {
        #expect(DeviceIcon.symbol(name: name, transport: transport) == symbol)
    }

    @Test(arguments: [
        ("User's AirPods Max", Transport.bluetooth, "airpodsmax"),
        ("User's AirPods Pro", .bluetooth, "airpodspro"),
        ("AirPods", .bluetooth, "airpods"),
        ("Jabra Evolve2 65", .bluetooth, "headphones"),
        ("Logitech USB Headset", .usb, "headphones"),
        ("Insta360 Link", .usb, "web.camera"),
        ("Elgato Facecam", .usb, "web.camera"),
        ("Logitech BRIO 500", .usb, "web.camera"),
        ("User's iPhone Microphone", .continuityWireless, "iphone"),
        ("Desk Monitor", .displayPort, "display"),
        ("ZoomAudioDevice", .virtual, "waveform"),
        ("Aggregate Device", .aggregate, "waveform"),
    ])
    func otherDevices(name: String, transport: Transport, symbol: String) {
        #expect(DeviceIcon.symbol(name: name, transport: transport) == symbol)
    }

    /// "HS" and "Link" only count as whole words, so they don't match inside other names.
    @Test func shortKeywordsNeedWholeWords() {
        #expect(DeviceIcon.symbol(name: "Sony LinkBuds", transport: .usb) == "mic")
        #expect(DeviceIcon.symbol(name: "Bushnell Recorder", transport: .usb) == "mic")
        #expect(DeviceIcon.symbol(name: "HS70 Pro", transport: .usb) == "headphones")
    }

    @Test func everySymbolExists() {
        let symbols = Set(DeviceIcon.nameRules.map(\.symbol))
            .union(["laptopcomputer", "waveform", "display", "iphone", "headphones", "mic", "mic.fill"])
        for symbol in symbols {
            #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "\(symbol)")
        }
    }

    @Test func transportCodes() {
        #expect(Transport(code: kAudioDeviceTransportTypeBuiltIn) == .builtIn)
        #expect(Transport(code: kAudioDeviceTransportTypeUSB) == .usb)
        #expect(Transport(code: kAudioDeviceTransportTypeVirtual) == .virtual)
        #expect(Transport(code: 0x6E6F7065) == .unknown)  // 'nope'
        #expect(fourCC(kAudioDeviceTransportTypeUSB) == "usb ")
        #expect(fourCC(0) == "0")
    }
}
