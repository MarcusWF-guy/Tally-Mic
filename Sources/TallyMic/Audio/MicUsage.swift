import CoreAudio
import Foundation

/// Which apps are recording from a microphone right now (SPEC 5.1). Core Audio keeps a process
/// object for every app that uses audio and says whether each is doing input. Reading this needs no
/// microphone permission, and Tally Mic never records itself, so it never counts itself.
enum MicUsage {
    /// Bundle IDs of the apps recording now, sorted. Apps without one show as "pid 123".
    static func recordingApps() -> [String] {
        AudioHAL.processIDs().filter(isRecording).map(name).sorted()
    }

    static func isRecording(_ process: AudioObjectID) -> Bool {
        AudioHAL.read(process, runningInput, as: UInt32(0)) == 1
    }

    static func name(_ process: AudioObjectID) -> String {
        if let bundleID = AudioHAL.readString(process, kAudioProcessPropertyBundleID), !bundleID.isEmpty {
            return bundleID
        }
        let pid = AudioHAL.read(process, AudioHAL.address(kAudioProcessPropertyPID), as: pid_t(0)) ?? 0
        return "pid \(pid)"
    }

    static var runningInput: AudioObjectPropertyAddress { AudioHAL.address(kAudioProcessPropertyIsRunningInput) }
    /// Whether an app is doing any audio. Unlike `runningInput`, macOS announces when this changes.
    static var runningAnything: AudioObjectPropertyAddress { AudioHAL.address(kAudioProcessPropertyIsRunning) }
    /// Whether any app is using an input device. Also announced when it changes.
    static var deviceRunning: AudioObjectPropertyAddress { AudioHAL.address(kAudioDevicePropertyDeviceIsRunningSomewhere) }
}
