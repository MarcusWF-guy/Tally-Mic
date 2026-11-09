import CoreAudio
import Foundation

/// How an input can be muted (SPEC 7.5): its own mute switch
/// (`kAudioDevicePropertyMute`), else its volume set to zero and back, else not at all. In testing,
/// every input but an iPhone's had a settable mute; the iPhone has neither.
enum MuteControl: Equatable, Sendable {
    case mute
    case volume(VolumeControl)
    case none

    static func find(for device: AudioObjectID) -> MuteControl {
        if AudioHAL.isSettable(device, address) { return .mute }
        let volume = VolumeControl.find(for: device)
        return volume == .none ? .none : .volume(volume)
    }

    /// The device's own mute state, when it has a mute switch.
    func isMuted(_ device: AudioObjectID) -> Bool? {
        guard self == .mute else { return nil }
        return AudioHAL.read(device, Self.address, as: UInt32(0)).map { $0 != 0 }
    }

    static var address: AudioObjectPropertyAddress {
        AudioHAL.address(kAudioDevicePropertyMute, kAudioObjectPropertyScopeInput)
    }
}
