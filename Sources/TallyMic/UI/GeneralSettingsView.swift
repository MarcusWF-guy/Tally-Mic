import AppKit
import ServiceManagement
import SwiftUI

/// Settings > General's state. Owned by SettingsWindowController, because SwiftUI's `@State`
/// doesn't build with only the Command Line Tools (SPEC 11).
@MainActor
@Observable
final class GeneralSettingsState {
    var loginStatus = LoginItem.status
    var diagnosticsCopied = false

    func copyDiagnostics() {
        let report = Diagnostics.report(Diagnostics.current())
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        Log.info("Diagnostics copied")
        diagnosticsCopied = true
        Task {
            try? await Task.sleep(for: .seconds(3))
            diagnosticsCopied = false
        }
    }
}

/// Settings > General (SPEC 5.5).
struct GeneralSettingsView: View {
    let config: ConfigStore
    let state: GeneralSettingsState
    let model: AppModel
    let setPreferredOrder: (Bool) -> Void
    let setMonitorVolume: (Bool) -> Void

    /// The classic app Settings layout Apple's own apps use (Safari, Mail, Notes): labels on the
    /// left ending in a colon, controls on the right, thin dividers between groups (SPEC 5.5).
    /// A Grid rather than a `.columns` Form, because the Form only draws dividers across the
    /// control column, and Apple's Settings windows run them the full width.
    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 14) {
            row("Startup:") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Launch at login", isOn: Binding(
                        get: { state.loginStatus == .enabled || state.loginStatus == .requiresApproval },
                        set: { on in
                            LoginItem.set(on, config: config)
                            state.loginStatus = LoginItem.status
                        }))
                    .toggleStyle(.checkbox)
                    if state.loginStatus == .requiresApproval {
                        note("macOS needs you to allow Tally Mic in Login Items.")
                        Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
            }

            divider

            // SPEC 6.2: automatic switching.
            row("Preferred order:") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Switch microphones automatically", isOn: Binding(
                        get: { model.preferredOrderEnabled },
                        set: { setPreferredOrder($0) }))
                    .toggleStyle(.checkbox)
                    note("Uses the first available microphone in the active setup's order (see Setups). A headset's microphone is only used while that headset is the sound output. Picking a microphone yourself turns this off. Also in the menu.")
                }
            }

            divider

            // SPEC 7.7: the volume keys change a monitor's volume while the sound plays through it.
            row("Volume keys:") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Control external monitor volume", isOn: Binding(
                        get: { model.monitorVolumeEnabled },
                        set: { setMonitorVolume($0) }))
                    .toggleStyle(.checkbox)
                    if model.monitorVolumeEnabled && model.monitorVolumeNeedsAccess {
                        note("Allow Tally Mic in Privacy & Security > Accessibility, so it can use the volume keys.")
                        Button("Open Accessibility Settings…") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            }

            divider

            // SPEC 8: meeting apps only follow Tally Mic if they're set to follow the system.
            row("Meeting apps:") {
                note("In Zoom, Teams and Meet, set the microphone to follow the system (Zoom calls it \u{201C}Same as System\u{201D}). Otherwise they ignore what you pick in Tally Mic.")
            }

            divider

            row("Troubleshooting:") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button("Copy Diagnostics") { state.copyDiagnostics() }
                        if state.diagnosticsCopied {
                            note("Copied. Paste it to Claude.")
                        }
                    }
                    Button("Show Config File") { reveal(ConfigStore.defaultURL) }
                    Button("Show Log") { reveal(Log.fileURL) }
                }
            }

            divider

            // SPEC 11: teammates install from GitHub releases, so they need to know which one they have.
            row("Version:") {
                HStack(spacing: 12) {
                    Text(Bundle.main.versionDescription)
                    Button("Releases on GitHub…") { NSWorkspace.shared.open(Self.releasesPage) }
                        .help("Newer versions of Tally Mic, and how to install them")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        // The user may have changed it in System Settings since the window last showed.
        .onAppear { state.loginStatus = LoginItem.status }
    }

    static let releasesPage = URL(string: "https://github.com/MarcusWF-guy/Tally-Mic/releases")!

    /// A label ending in a colon, right-aligned, beside its controls.
    private func row(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        GridRow {
            Text(label)
                .gridColumnAlignment(.trailing)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Spans both columns, with a little extra room above and below.
    private var divider: some View {
        Divider()
            .gridCellUnsizedAxes(.horizontal)
            .padding(.vertical, 4)
    }

    /// Explanations under or beside a control, in the small grey text Apple's Settings windows use.
    private func note(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Shows the file in Finder, or its folder if the file doesn't exist yet.
    private func reveal(_ file: URL) {
        let folder = file.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: file.path) {
            NSWorkspace.shared.activateFileViewerSelecting([file])
        } else {
            NSWorkspace.shared.open(folder)
        }
    }
}
