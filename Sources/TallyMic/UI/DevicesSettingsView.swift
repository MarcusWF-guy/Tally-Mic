import SwiftUI

/// Settings > Devices (SPEC 5.5): every input Tally Mic has seen, connected or not. Each can be
/// hidden from the panel, given a shorter name, or forgotten once it's gone. The settings apply in
/// every setup.
struct DevicesSettingsView: View {
    let model: AppModel
    let settings: DeviceSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Table(model.knownDevices) {
                TableColumn("Show") { device in
                    Toggle("Show \(device.name) in the menu", isOn: Binding(
                        get: { device.visible },
                        set: { settings.setVisible($0, for: device) }))
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                }
                .width(36)

                TableColumn("Microphone") { device in
                    HStack(spacing: 6) {
                        Image(systemName: DeviceIcon.symbol(name: device.name, transport: Transport(rawValue: device.transport) ?? .unknown))
                            .frame(width: 16)
                            .accessibilityHidden(true)
                        Text(device.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .foregroundStyle(isConnected(device) ? .primary : .secondary)
                    .help(device.name)
                }
                .width(min: 160, ideal: 220)

                TableColumn("Name in Menu") { device in
                    // The real name shows greyed out until a name is typed. Saved as it's typed.
                    TextField(device.name, text: Binding(
                        get: { device.displayName ?? "" },
                        set: { settings.setDisplayName($0, for: device) }))
                    .onSubmit { settings.nameEditingEnded(for: device) }
                    .accessibilityLabel("Name in menu for \(device.name)")
                }
                .width(min: 120, ideal: 170)

                TableColumn("Status") { device in
                    if isConnected(device) {
                        Text("Connected")
                            .foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 6) {
                            Text("Not connected")
                                .foregroundStyle(.secondary)
                            Button("Forget") { settings.forget(device) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .help("Remove \(device.name) from this list. If it connects again, it's added back.")
                        }
                    }
                }
                .width(min: 170, ideal: 190)
            }
            .frame(height: 240)

            Text("Unticked microphones don't appear in the menu, unless one is the microphone in use. A name replaces the one macOS uses, in the menu only. Forget removes a microphone that isn't connected; if it comes back, it's added again.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
    }

    private func isConnected(_ device: KnownDevice) -> Bool {
        model.inputs.contains { $0.uid == device.uid }
    }
}
