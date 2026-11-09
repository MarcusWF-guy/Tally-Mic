import CoreAudio
import Observation

/// Everything the UI shows. AudioSystem writes to it; SwiftUI views and the status item read it.
@MainActor
@Observable
final class AppModel {
    /// Connected inputs, sorted by name (SPEC 5.3).
    var inputs: [InputDevice] = []
    /// The system input. Nil if macOS reports none.
    var currentInputID: AudioObjectID?
    /// The current input's volume, 0 to 1. Nil when it has no volume Tally Mic can set (SPEC 7.3).
    var volume: Float?
    /// Bundle IDs of the apps recording from a microphone right now (SPEC 5.1).
    var recordingApps: [String] = []
    /// Every input Tally Mic has seen, connected or not, with the user's names and show/hide
    /// choices from the Devices tab (SPEC 5.5).
    var knownDevices: [KnownDevice] = []
    /// External displays connected now, and every one seen before (SPEC 6.1).
    var displays: [DisplayID] = []
    var knownDisplays: [DisplayID] = []
    /// The setups, in the order they're checked; the fallback is last (SPEC 6.1).
    var setups: [Setup] = [Setup.firstRun]
    /// SPEC 6.2: automatic switching, on or off (General tab).
    var preferredOrderEnabled = false
    var lidClosed = false
    /// The sound output's UID. A headset's mic follows its headphones (SPEC 6.2).
    var outputUID: String?
    /// Universal mute (SPEC 7.5): the current input is muted, and the next one will be too.
    var isMuted = false
    /// Whether the current input has a mute switch or a volume to set to zero.
    var canMuteCurrent = true
    /// Keyboard shortcuts set in the Shortcuts tab (SPEC 7.6), and any macOS refused because
    /// something else already uses them.
    var shortcuts: [ShortcutAction: Shortcut] = [:]
    var refusedShortcuts: Set<ShortcutAction> = []
    /// SPEC 7.7: the volume keys change a monitor's volume (General tab), and whether that's
    /// waiting on Accessibility permission.
    var monitorVolumeEnabled = false
    var monitorVolumeNeedsAccess = false
    /// Muted for real: the menu bar icon and panel show this, never a mute that isn't happening.
    var effectivelyMuted: Bool { isMuted && canMuteCurrent }

    var currentInput: InputDevice? { inputs.first { $0.objectID == currentInputID } }
    var activeSetup: Setup { SetupResolver.active(setups, connected: displays) }
    var micInUse: Bool { !recordingApps.isEmpty }
    /// The panel's rows, in the active setup's order (SPEC 5.3).
    var shownInputs: [ShownDevice] {
        DeviceList.shown(inputs: inputs, known: knownDevices, currentID: currentInputID,
                         order: SetupResolver.fullOrder(activeSetup, known: knownDevices).map(\.uid))
    }

    /// The name the panel uses for an input: the user's, or the one macOS reports.
    func shownName(of device: InputDevice) -> String {
        knownDevices.first { $0.uid == device.uid }?.displayName ?? device.name
    }
}

/// Re-runs `apply` whenever an observable value it read changes. For AppKit code that
/// can't use SwiftUI's automatic tracking, like the status item.
@MainActor
func trackChanges(_ apply: @escaping @MainActor () -> Void) {
    withObservationTracking(apply) {
        Task { @MainActor in trackChanges(apply) }
    }
}
