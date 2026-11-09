import SwiftUI

/// What the panel can ask for. Closures, so the panel can be laid out in tests without Core Audio.
struct PanelActions {
    var select: (InputDevice) -> Void
    var setAutoSwitching: (Bool) -> Void
    var setMuted: (Bool) -> Void
    var setVolume: (Float) -> Void
    var openTallySettings: () -> Void
    var openSoundSettings: () -> Void
}

/// The panel's contents (SPEC 5.3), laid out like the Sound menu: title, volume slider, the
/// input list, and a footer with "Tally Mic Settings…" and "Sound Settings…".
struct PanelView: View {
    let model: AppModel
    let actions: PanelActions
    let hover: HoverState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Microphone")
                .font(.system(size: 13, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
                // SPEC 7.5: the mic on or muted, like the switch beside "Wi-Fi" in its panel. An
                // overlay, so the title row keeps the height it was measured at.
                .overlay(alignment: .trailing) { muteSwitch }
                .padding(.horizontal, PanelMetrics.inset)
                .padding(.top, Spacing.titleTop)
                .padding(.bottom, Spacing.titleBottom)
            VolumeSlider(volume: model.volume, deviceName: model.currentInput.map(model.shownName), onChange: actions.setVolume)
                .opacity(model.effectivelyMuted ? 0.45 : 1)
                .padding(.leading, Spacing.sliderLeading)
                .padding(.trailing, Spacing.sliderTrailing)
                .padding(.bottom, Spacing.sliderBottom)
            PanelDivider()
            SectionHeader(title: "Input")
            let shown = model.shownInputs
            if shown.isEmpty {
                Text("No microphones found")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, PanelMetrics.inset)
                    .padding(.vertical, 6)
            }
            // Hidden inputs are left out, and named ones use their names (SPEC 5.3, 5.5).
            ForEach(shown) { row in
                let isActive = row.device.objectID == model.currentInputID
                DeviceRow(
                    id: row.device.uid, name: row.name, symbol: row.device.symbol,
                    isActive: isActive, note: nil, hover: hover
                ) {
                    actions.select(row.device)
                }
            }
            // SPEC 5.3: the setup Tally Mic detected, and automatic switching on or off. Always here.
            PanelDivider()
                .padding(.top, Spacing.aboveSetupDivider)
                .padding(.bottom, 4)
            SetupSection(
                setupName: model.activeSetup.name, autoSwitching: model.preferredOrderEnabled,
                setAutoSwitching: actions.setAutoSwitching)
            PanelDivider(inset: PanelMetrics.footerDividerInset)
                .padding(.top, Spacing.aboveFooterDivider)
            footer
        }
        .frame(width: PanelMetrics.width)
        .panelBackground()
        // Transparent room for the drawn shadow. None at the top, so the window never covers
        // the menu bar.
        .padding(.horizontal, PanelMetrics.shadowSide)
        .padding(.bottom, PanelMetrics.shadowBottom)
    }

    /// On while the microphone is live, off while muted.
    private var muteSwitch: some View {
        Toggle("Microphone on", isOn: Binding(
            get: { !model.effectivelyMuted },
            set: { actions.setMuted(!$0) }))
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.small)
        .disabled(!model.canMuteCurrent)
        .help(model.canMuteCurrent
            ? (model.effectivelyMuted ? "Unmute the microphone" : "Mute the microphone, whichever one is in use")
            : "\(model.currentInput.map(model.shownName) ?? "This microphone") can't be muted")
        .accessibilityLabel("Microphone")
        .accessibilityValue(model.effectivelyMuted ? "Muted" : "On")
    }

    /// Two buttons sharing one row, each styled like "Sound Settings…" at the bottom of the Sound
    /// panel: Tally Mic's own settings on the left, macOS's Sound settings on the right.
    private var footer: some View {
        HStack(spacing: 0) {
            footerButton("Tally Mic Settings…", id: "footer:tally", alignment: .leading,
                         action: actions.openTallySettings)
            footerButton("Sound Settings…", id: "footer:sound", alignment: .trailing,
                         action: actions.openSoundSettings)
        }
        .padding(.top, Spacing.footerTop)
        .padding(.bottom, Spacing.footerBottom)
    }

    /// Vertical spacing, tuned until an offscreen render of this panel lined up with the Sound
    /// panel's screenshot to the pixel (SPEC 5.3).
    private enum Spacing {
        static let titleTop: CGFloat = 14
        static let titleBottom: CGFloat = 8.5
        static let sliderBottom: CGFloat = 10
        /// Puts the track exactly where the Sound panel's is. Its track sits left of center,
        /// because its loud speaker icon is much wider than the quiet one; the two mic icons are
        /// the same width, so the room is on the right.
        static let sliderLeading: CGFloat = 12.5
        static let sliderTrailing: CGFloat = 23
        static let aboveFooterDivider: CGFloat = 5
        static let aboveSetupDivider: CGFloat = 5
        static let footerTop: CGFloat = 1.5
        static let footerBottom: CGFloat = 3.5
        static let footerButtonVertical: CGFloat = 6
    }

    private func footerButton(
        _ title: String, id: String, alignment: Alignment, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: alignment)
                .padding(.horizontal, PanelMetrics.inset)
                .padding(.vertical, Spacing.footerButtonVertical)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(id, in: hover)
    }
}
