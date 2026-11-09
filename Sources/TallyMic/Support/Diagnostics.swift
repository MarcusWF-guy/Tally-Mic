import CoreAudio
import Foundation

/// Copy Diagnostics (SPEC 10): everything Claude needs to debug Tally Mic, as plain text.
/// Settings > General copies it; `TallyMic --diagnostics` prints it.
enum Diagnostics {
    struct DeviceReport: Equatable {
        var device: InputDevice
        var channels: Int
        var volume: VolumeControl
        /// 0 to 1, nil when there's no volume to read.
        var level: Float?
    }

    struct Snapshot {
        var appVersion: String
        var macOS: String
        var date: Date
        var lidClosed: Bool?
        var currentInputID: AudioObjectID?
        /// Bundle IDs of the apps recording from a microphone.
        var recordingApps: [String] = []
        /// External displays connected now.
        var displays: [DisplayID] = []
        /// The sound output's name.
        var output: String?
        /// The current input's own mute switch, if it has one.
        var currentMuted: Bool?
        /// How the sound output is connected, and whether macOS can set its volume (SPEC 7.7).
        var outputTransport: String?
        var outputHasVolume: Bool?
        /// Accessibility permission, which the volume keys need for a monitor (SPEC 7.7).
        var accessibilityAllowed: Bool?
        /// Where the Sound icon is, which the volume bubble sits under (SPEC 7.7).
        var soundIcon: String?
        var devices: [DeviceReport]
        var config: String?
        var logLines: [String]
    }

    /// Reads the system as it is right now. Changes nothing.
    @MainActor
    static func current() -> Snapshot {
        let devices = InputDevice.readAll().map { device in
            let volume = VolumeControl.find(for: device.objectID)
            return DeviceReport(
                device: device, channels: AudioHAL.inputChannelCount(device.objectID),
                volume: volume, level: volume.read(from: device.objectID))
        }
        return Snapshot(
            appVersion: Bundle.main.versionDescription,
            macOS: ProcessInfo.processInfo.operatingSystemVersionString,
            date: .now,
            lidClosed: Lid.isClosed(),
            currentInputID: AudioHAL.defaultInputDevice(),
            recordingApps: MicUsage.recordingApps(),
            displays: DisplayMonitor.connectedExternalDisplays(),
            output: AudioHAL.read(AudioHAL.system, AudioHAL.address(kAudioHardwarePropertyDefaultOutputDevice), as: AudioObjectID(0))
                .flatMap { AudioHAL.readString($0, kAudioObjectPropertyName) },
            currentMuted: AudioHAL.defaultInputDevice().flatMap { MuteControl.find(for: $0).isMuted($0) },
            outputTransport: AudioHAL.defaultOutputDevice()
                .flatMap { AudioHAL.read($0, AudioHAL.address(kAudioDevicePropertyTransportType), as: UInt32(0)) }
                .map(fourCC),
            outputHasVolume: AudioHAL.defaultOutputDevice().map(AudioHAL.hasOutputVolume),
            accessibilityAllowed: VolumeKeyTap.isAllowed,
            soundIcon: MenuBarExtras.report(),
            devices: devices,
            config: try? String(contentsOf: ConfigStore.defaultURL, encoding: .utf8),
            logLines: Log.lastLines(50))
    }

    static func report(_ snapshot: Snapshot) -> String {
        let lid = snapshot.lidClosed.map { $0 ? "closed" : "open" } ?? "unknown"
        let currentName: String? = snapshot.devices.first { $0.device.objectID == snapshot.currentInputID }?.device.name
        let current = currentName
            ?? snapshot.currentInputID.map { "device \($0), not an input Tally Mic lists" } ?? "none"
        let recording = snapshot.recordingApps.isEmpty ? "nothing" : snapshot.recordingApps.joined(separator: ", ")
        var lines: [String] = [
            "Tally Mic \(snapshot.appVersion) diagnostics, \(snapshot.date.formatted(.iso8601))",
            "macOS \(snapshot.macOS)",
            "Lid: \(lid)",
            "Current input: \(current)",
            "Recording now: \(recording)",
            "Sound output: \(snapshot.output ?? "none")"
                + (snapshot.outputTransport.map { " (\($0)" + (snapshot.outputHasVolume == false ? ", no volume control in macOS)" : ")") } ?? ""),
            "Accessibility: " + (snapshot.accessibilityAllowed.map { $0 ? "allowed" : "not allowed" } ?? "unknown"),
            "Sound icon: \(snapshot.soundIcon ?? "unknown")",
            "Current input muted: " + (snapshot.currentMuted.map { $0 ? "yes" : "no" } ?? "no mute switch"),
            "External displays: " + (snapshot.displays.isEmpty ? "none" : snapshot.displays.map { "\($0.name) (vendor \($0.vendorID), model \($0.modelID), serial \($0.serial))" }.joined(separator: "; ")),
            "",
            "Inputs (\(snapshot.devices.count)):",
        ]
        for report in snapshot.devices {
            let device = report.device
            let current = device.objectID == snapshot.currentInputID ? " [current]" : ""
            let level = report.level.map { ", now \(Int(($0 * 100).rounded()))%" } ?? ""
            lines += [
                "- \(device.name)\(current)",
                "  UID: \(device.uid)",
                "  Transport: \(device.transport.rawValue) ('\(fourCC(device.transportCode))'), icon \(device.symbol)",
                "  Channels: \(report.channels)",
                "  Volume: \(report.volume.summary)\(level)",
            ]
        }
        lines += ["", "Config (\(ConfigStore.defaultURL.path)):", snapshot.config ?? "(none yet)"]
        lines += ["", "Last \(snapshot.logLines.count) log lines (\(Log.fileURL.path)):"]
        lines += snapshot.logLines.isEmpty ? ["(none)"] : snapshot.logLines
        return lines.joined(separator: "\n")
    }
}

extension Bundle {
    var versionDescription: String {
        let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(version) (\(build))"
    }
}
