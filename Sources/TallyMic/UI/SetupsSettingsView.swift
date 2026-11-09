import SwiftUI

/// Which setup the Setups tab shows. Owned by SettingsWindowController, because SwiftUI's `@State`
/// doesn't build with only the Command Line Tools (SPEC 11).
@MainActor
@Observable
final class SetupsTabState {
    var selectedID: String?
}

/// Settings > Setups (SPEC 5.5, 6.1): the setups on the left, checked top to bottom, and the
/// selected one's details on the right: its name, the display that makes it active, and its
/// preferred order of microphones.
struct SetupsSettingsView: View {
    let model: AppModel
    let settings: SetupSettings
    let state: SetupsTabState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let display = SetupResolver.unusedDisplays(model.setups, connected: model.displays).first {
                offer(for: display)
            }
            HStack(alignment: .top, spacing: 20) {
                setupList
                    .frame(width: 180)
                if let setup = selected {
                    detail(setup)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        // Without this the content shrinks to fit and drifts to the middle when the offer above
        // isn't showing.
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(20)
    }

    /// The setup shown on the right: the one picked in the list, else the active one.
    private var selected: Setup? {
        model.setups.first { $0.id == state.selectedID } ?? model.setups.first { $0.id == model.activeSetup.id }
    }

    /// SPEC 6.1: an external display is connected that no setup uses.
    private func offer(for display: DisplayID) -> some View {
        HStack {
            Text("\(display.name) is connected, but no setup uses it.")
            Spacer()
            Button("Add a Setup for \(display.name)") {
                state.selectedID = settings.add(for: display)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary.opacity(0.6)))
    }

    private var setupList: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: Binding(get: { selected?.id }, set: { state.selectedID = $0 })) {
                ForEach(model.setups) { setup in
                    HStack {
                        Text(title(setup))
                        Spacer()
                        if setup.id == model.activeSetup.id {
                            Text("Active")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(setup.id)
                }
                // The fallback stays last whatever is dragged where (SetupResolver.normalized).
                .onMove { settings.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.bordered)
            .frame(height: 230)

            HStack(spacing: 0) {
                Button {
                    if let id = settings.add() { state.selectedID = id }
                } label: {
                    Image(systemName: "plus").frame(width: 26, height: 22)
                }
                .disabled(settings.displayForNewSetup == nil)
                .help(settings.displayForNewSetup.map { "Add a setup for \($0.name)" }
                    ?? "Connect an external display to add a setup for it")
                .accessibilityLabel("Add Setup")

                Button {
                    if let setup = selected {
                        settings.delete(setup.id)
                        state.selectedID = nil
                    }
                } label: {
                    Image(systemName: "minus").frame(width: 26, height: 22)
                }
                .disabled(selected?.isFallback ?? true)
                .help("Delete the selected setup. The last setup can't be deleted: it's used when no other setup's display is connected.")
                .accessibilityLabel("Delete Setup")
            }
            .buttonStyle(.borderless)
            .padding(.top, 4)

            Text("Checked top to bottom. Drag to reorder.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        }
    }

    private func detail(_ setup: Setup) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 12) {
            GridRow {
                Text("Name:")
                    .gridColumnAlignment(.trailing)
                TextField("Untitled", text: Binding(
                    get: { setup.name },
                    set: { settings.rename(setup.id, to: $0) }))
                .frame(maxWidth: 220)
            }
            GridRow {
                Text("Active when:")
                activeWhen(setup)
            }
            if !setup.isFallback {
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    Button("Use Current Display") {
                        if let display = model.displays.first { settings.setTrigger(setup.id, to: display) }
                    }
                    .disabled(model.displays.isEmpty)
                    .help("Make this setup active when the display connected now is connected")
                }
            }
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                if setup.id == model.activeSetup.id {
                    Label("Active now", systemImage: "circle.fill")
                        .labelStyle(StatusLabelStyle(color: .green))
                } else {
                    Label("Not active", systemImage: "circle.fill")
                        .labelStyle(StatusLabelStyle(color: .secondary))
                }
            }
            GridRow(alignment: .top) {
                Text("Order:")
                orderList(setup)
            }
        }
    }

    @ViewBuilder
    private func activeWhen(_ setup: Setup) -> some View {
        if let trigger = setup.trigger {
            HStack(spacing: 8) {
                Picker("Display", selection: Binding(
                    get: { trigger },
                    set: { settings.setTrigger(setup.id, to: $0) })
                ) {
                    ForEach(displayChoices(including: trigger), id: \.self) { display in
                        Text(display.name).tag(display)
                    }
                }
                .labelsHidden()
                .fixedSize()
                Text("is connected")
                    .fixedSize()
            }
        } else {
            Text("No other setup's display is connected")
                .foregroundStyle(.secondary)
        }
    }

    private func orderList(_ setup: Setup) -> some View {
        let devices = SetupResolver.fullOrder(setup, known: model.knownDevices)
        return VStack(alignment: .leading, spacing: 8) {
            List {
                ForEach(Array(devices.enumerated()), id: \.element.uid) { index, device in
                    HStack(spacing: 8) {
                        Text("\(index + 1)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 18, alignment: .trailing)
                        Image(systemName: DeviceIcon.symbol(
                            name: device.name, transport: Transport(rawValue: device.transport) ?? .unknown))
                            .frame(width: 16)
                            .accessibilityHidden(true)
                        Text(device.shownName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text(note(device))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(device.visible ? .primary : .secondary)
                }
                .onMove { settings.moveDevices(in: setup.id, fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.bordered)
            // A Grid column sizes to its contents, so the list gets the width the tab has room for.
            .frame(width: 410, height: 200)

            Text("Tally Mic uses the first microphone in this list that's connected. Drag to reorder. Hidden microphones are skipped, and so is a headset unless it's the sound output." + (model.preferredOrderEnabled ? "" : " Automatic switching is off: turn it on in General or the menu."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 410, alignment: .leading)
        }
    }

    private func note(_ device: KnownDevice) -> String {
        if !device.visible { return "Hidden" }
        return model.inputs.contains { $0.uid == device.uid } ? "" : "Not connected"
    }

    private func title(_ setup: Setup) -> String {
        let name = setup.name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Untitled" : name
    }

    /// Every display seen before, plus the trigger itself if it isn't among them.
    private func displayChoices(including trigger: DisplayID) -> [DisplayID] {
        model.knownDisplays.contains(trigger) ? model.knownDisplays : model.knownDisplays + [trigger]
    }
}

/// A small colored dot before secondary text, for "Active now".
private struct StatusLabelStyle: LabelStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
                .font(.system(size: 7))
                .foregroundStyle(color)
            configuration.title
                .foregroundStyle(.secondary)
        }
    }
}
