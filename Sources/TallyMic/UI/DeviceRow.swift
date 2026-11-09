import SwiftUI

/// One input in the panel (SPEC 5.3), copied from Tally Cam's profile row: a round icon, filled
/// with the accent color for the active device, and the device's name. Highlights under the pointer
/// like native menu rows.
struct DeviceRow: View {
    /// The device's UID, so two mics with the same name highlight on their own.
    let id: String
    let name: String
    let symbol: String
    let isActive: Bool
    /// Secondary text at the trailing edge, such as "Auto" (Milestone 3).
    let note: String?
    let hover: HoverState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isActive ? Color.white : Color.primary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(isActive ? AnyShapeStyle(Color.accentColor) : PanelMetrics.circleFill))
                Text(name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)
                // No minimum: the stack's own 8 pt spacing already separates the note, and a longer
                // minimum cut off names the Sound panel shows in full.
                Spacer(minLength: 0)
                if let note {
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, PanelMetrics.inset)
            .padding(.vertical, 3)  // 32 pt per row, like the Sound panel.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight("device:\(id)", in: hover)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityValue([isActive ? "Active" : nil, note].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
