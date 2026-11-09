import CoreAudio
import Foundation

/// Typed helpers over Core Audio's property API (SPEC 7). Every call is synchronous and safe from
/// any thread; Tally Mic makes them on the main thread.
enum AudioHAL {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    static func address(
        _ selector: AudioObjectPropertySelector,
        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static func has(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        return AudioObjectHasProperty(object, &address)
    }

    static func isSettable(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(object, &address),
              AudioObjectIsPropertySettable(object, &address, &settable) == noErr else { return false }
        return settable.boolValue
    }

    /// Reads a fixed-size value, or nil if the object doesn't have the property.
    static func read<T: BitwiseCopyable>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, as initial: T) -> T? {
        var address = address
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    @discardableResult
    static func write<T: BitwiseCopyable>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ value: T) -> OSStatus {
        var address = address
        var value = value
        return AudioObjectSetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<T>.size), &value)
    }

    static func readString(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr, let value else {
            return nil
        }
        // Core Audio hands back a string the caller owns.
        return value.takeRetainedValue() as String
    }

    static func deviceIDs() -> [AudioObjectID] { systemObjects(kAudioHardwarePropertyDevices) }

    /// Every app Core Audio knows about, as process objects (macOS 14 and later).
    static func processIDs() -> [AudioObjectID] { systemObjects(kAudioHardwarePropertyProcessObjectList) }

    /// A list of object IDs the system object holds, such as its devices or processes.
    private static func systemObjects(_ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var address = address(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    /// SPEC 7.1: a device is an input if it has at least one input stream.
    static func hasInputStreams(_ device: AudioObjectID) -> Bool {
        var address = address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    static func inputChannelCount(_ device: AudioObjectID) -> Int {
        var address = address(kAudioDevicePropertyStreamConfiguration, kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, buffer) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(buffer.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    static func hasOutputStreams(_ device: AudioObjectID) -> Bool {
        var address = address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    /// Other devices that are the same hardware, such as a headset's mic and headphones.
    static func relatedDevices(_ device: AudioObjectID) -> [AudioObjectID] {
        var address = address(kAudioDevicePropertyRelatedDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.filter { $0 != device }
    }

    /// The sound output's UID.
    static func defaultOutputUID() -> String? {
        let id = read(system, address(kAudioHardwarePropertyDefaultOutputDevice), as: AudioObjectID(0)) ?? 0
        return id == 0 ? nil : readString(id, kAudioDevicePropertyDeviceUID)
    }

    static func defaultOutputDevice() -> AudioObjectID? {
        let id = read(system, address(kAudioHardwarePropertyDefaultOutputDevice), as: AudioObjectID(0))
        return id == 0 ? nil : id
    }

    /// A display's speakers or audio out, reached over DisplayPort or HDMI (SPEC 7.7).
    static func isDisplayOutput(_ device: AudioObjectID) -> Bool {
        let transport = read(device, address(kAudioDevicePropertyTransportType), as: UInt32(0))
        return transport == kAudioDeviceTransportTypeDisplayPort || transport == kAudioDeviceTransportTypeHDMI
    }

    /// Whether macOS can set this output's volume, on the main element or the first channel.
    /// Sound sent to a monitor usually can't be, which is why the volume keys stop working there.
    static func hasOutputVolume(_ device: AudioObjectID) -> Bool {
        [kAudioObjectPropertyElementMain, 1].contains {
            isSettable(device, address(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, $0))
        }
    }

    static func defaultInputDevice() -> AudioObjectID? {
        let id = read(system, address(kAudioHardwarePropertyDefaultInputDevice), as: AudioObjectID(0))
        return id == 0 ? nil : id
    }
}

/// A Core Audio property listener (SPEC 7.4). Callbacks arrive on the main queue.
struct PropertyListener {
    let object: AudioObjectID
    let address: AudioObjectPropertyAddress
    private let block: AudioObjectPropertyListenerBlock

    static func add(
        _ object: AudioObjectID, _ address: AudioObjectPropertyAddress,
        _ handler: @escaping @MainActor () -> Void
    ) -> PropertyListener? {
        var address = address
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            MainActor.assumeIsolated { handler() }
        }
        let status = AudioObjectAddPropertyListenerBlock(object, &address, DispatchQueue.main, block)
        guard status == noErr else {
            Log.error("Couldn't listen for \(fourCC(address.mSelector)) on device \(object) (status \(status))")
            return nil
        }
        return PropertyListener(object: object, address: address, block: block)
    }

    func remove() {
        var address = address
        // Fails harmlessly when the device has already gone away.
        AudioObjectRemovePropertyListenerBlock(object, &address, DispatchQueue.main, block)
    }
}

/// Core Audio's four-letter codes as text, for logs and diagnostics ('usb ', 'bltn').
func fourCC(_ code: UInt32) -> String {
    let bytes = [24, 16, 8, 0].map { UInt8((code >> UInt32($0)) & 0xFF) }
    guard bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) else { return String(code) }
    return String(decoding: bytes, as: UTF8.self)
}
