import SwiftUI

/// Settings > Shortcuts (SPEC 7.6): optional global keyboard shortcuts, none set until the user
/// sets one. The classic Settings layout, like the other tabs.
struct ShortcutsSettingsView: View {
    let model: AppModel
    let settings: ShortcutSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Every shortcut box in one column; labels right-aligned beside them, microphones by name.
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 12) {
                row("Mute or unmute:", .toggleMute)
                row("Automatic switching:", .toggleAutoSwitching)
                row("Open the menu:", .openMenu)

                divider

                GridRow {
                    Text("Switch to:")
                        .gridColumnAlignment(.trailing)
                    Text("A microphone's shortcut picks it, and turns automatic switching off.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(model.knownDevices) { device in
                    GridRow {
                        Text(device.shownName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 200, alignment: .trailing)
                            .foregroundStyle(device.visible ? .primary : .secondary)
                        recorder(.selectInput(uid: device.uid), label: "Switch to \(device.shownName)")
                    }
                }
            }

            Text("Shortcuts work in every app, ahead of the app's own, so pick keys your apps don't use, such as ⌃⌥M. Click a box and type the keys, with at least one of ⌘, ⌥ or ⌃ (function keys work alone). While typing, Delete clears a shortcut and Esc cancels.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ label: String, _ action: ShortcutAction) -> some View {
        GridRow {
            Text(label)
                .gridColumnAlignment(.trailing)
            recorder(action, label: label.replacingOccurrences(of: ":", with: ""))
        }
    }

    private func recorder(_ action: ShortcutAction, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                ShortcutRecorder(
                    shortcut: model.shortcuts[action], label: label,
                    onChange: { settings.set($0, for: action) },
                    onRecordingChange: { settings.setRecording($0) })
                .fixedSize()
                if model.shortcuts[action] != nil {
                    Button {
                        settings.set(nil, for: action)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Clear this shortcut")
                    .accessibilityLabel("Clear \(label) shortcut")
                }
            }
            // On its own line: beside the box it's cut off.
            if model.refusedShortcuts.contains(action) {
                Text("macOS already uses this shortcut. Pick another.")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var divider: some View {
        Divider()
            .gridCellUnsizedAxes(.horizontal)
            .padding(.vertical, 4)
    }
}
