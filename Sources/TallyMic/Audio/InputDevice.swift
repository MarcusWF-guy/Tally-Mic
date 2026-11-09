import CoreAudio
import Foundation

/// One input device macOS reports (SPEC 7.1). Identified by its UID, which survives reconnects;
/// the object ID is only valid while the device is connected.
struct InputDevice: Identifiable, Equatable, Sendable {
    let objectID: AudioObjectID
    let uid: String
    var name: String
    let transport: Transport
    /// Core Audio's raw transport code, for diagnostics when `transport` is `.unknown`.
    let transportCode: UInt32
    /// UIDs of the output devices that are the same hardware: a headset's headphones, the MacBook's
    /// speakers. From `kAudioDevicePropertyRelatedDevices`, plus the device itself if it has outputs.
    var outputUIDs: [String] = []

    var id: String { uid }
    var symbol: String { DeviceIcon.symbol(name: name, transport: transport) }
    /// A headset or earbuds, going by the same rules as its icon (SPEC 5.4).
    var isHeadset: Bool { DeviceIcon.isHeadset(symbol) }

    /// Reads every connected input device, sorted by name (SPEC 5.3).
    static func readAll() -> [InputDevice] {
        AudioHAL.deviceIDs()
            .filter(AudioHAL.hasInputStreams)
            .compactMap(read)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func read(_ objectID: AudioObjectID) -> InputDevice? {
        guard let uid = AudioHAL.readString(objectID, kAudioDevicePropertyDeviceUID) else { return nil }
        let code = AudioHAL.read(objectID, AudioHAL.address(kAudioDevicePropertyTransportType), as: UInt32(0)) ?? 0
        let outputs = ([objectID] + AudioHAL.relatedDevices(objectID))
            .filter(AudioHAL.hasOutputStreams)
            .compactMap { AudioHAL.readString($0, kAudioDevicePropertyDeviceUID) }
        return InputDevice(
            objectID: objectID, uid: uid,
            name: AudioHAL.readString(objectID, kAudioObjectPropertyName) ?? uid,
            transport: Transport(code: code), transportCode: code,
            outputUIDs: Array(NSOrderedSet(array: outputs)) as? [String] ?? outputs)
    }
}

/// How a device is connected (`kAudioDevicePropertyTransportType`). The raw values are what
/// config.json stores (SPEC 10).
enum Transport: String, Codable, Sendable, CaseIterable {
    case builtIn, usb, bluetooth, bluetoothLE, virtual, aggregate, autoAggregate
    case displayPort, hdmi, thunderbolt, continuityWired, continuityWireless
    case airPlay, firewire, pci, avb, unknown

    init(code: UInt32) {
        self = switch code {
        case kAudioDeviceTransportTypeBuiltIn: .builtIn
        case kAudioDeviceTransportTypeUSB: .usb
        case kAudioDeviceTransportTypeBluetooth: .bluetooth
        case kAudioDeviceTransportTypeBluetoothLE: .bluetoothLE
        case kAudioDeviceTransportTypeVirtual: .virtual
        case kAudioDeviceTransportTypeAggregate: .aggregate
        case kAudioDeviceTransportTypeAutoAggregate: .autoAggregate
        case kAudioDeviceTransportTypeDisplayPort: .displayPort
        case kAudioDeviceTransportTypeHDMI: .hdmi
        case kAudioDeviceTransportTypeThunderbolt: .thunderbolt
        case kAudioDeviceTransportTypeContinuityCaptureWired: .continuityWired
        case kAudioDeviceTransportTypeContinuityCaptureWireless: .continuityWireless
        case kAudioDeviceTransportTypeAirPlay: .airPlay
        case kAudioDeviceTransportTypeFireWire: .firewire
        case kAudioDeviceTransportTypePCI: .pci
        case kAudioDeviceTransportTypeAVB: .avb
        default: .unknown
        }
    }
}

/// Where a device's input volume can be set (SPEC 7.3): the main element, else every channel
/// that's settable, else nowhere.
enum VolumeControl: Equatable, Sendable {
    case none
    case main
    case channels([AudioObjectPropertyElement])

    static func find(for device: AudioObjectID) -> VolumeControl {
        if AudioHAL.isSettable(device, address(kAudioObjectPropertyElementMain)) { return .main }
        let channels = (1...max(1, AudioHAL.inputChannelCount(device)))
            .map { AudioObjectPropertyElement($0) }
            .filter { AudioHAL.isSettable(device, address($0)) }
        return channels.isEmpty ? .none : .channels(channels)
    }

    var elements: [AudioObjectPropertyElement] {
        switch self {
        case .none: []
        case .main: [kAudioObjectPropertyElementMain]
        case .channels(let channels): channels
        }
    }

    /// 0 to 1. The average of the channels when they're set one by one.
    func read(from device: AudioObjectID) -> Float? {
        let values = elements.compactMap { AudioHAL.read(device, Self.address($0), as: Float32(0)) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Float(values.count)
    }

    func write(_ value: Float, to device: AudioObjectID) {
        let clamped = Float32(min(max(value, 0), 1))
        for element in elements {
            let status = AudioHAL.write(device, Self.address(element), clamped)
            if status != noErr {
                Log.error("Couldn't set volume on device \(device), element \(element) (status \(status))")
            }
        }
    }

    /// For logs and diagnostics.
    var summary: String {
        switch self {
        case .none: "not settable"
        case .main: "settable (main element)"
        case .channels(let channels): "settable (channel\(channels.count == 1 ? "" : "s") \(channels.map(String.init).joined(separator: ", ")))"
        }
    }

    static func address(_ element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioHAL.address(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeInput, element)
    }
}
