import AppKit
import SwiftUI

/// Measured from Marcus's Retina screenshot of the Sound panel on macOS 27.2, pixel by pixel
/// (SPEC 5.2). The shadow is Tally Cam's, which Marcus picked from three variants side by side.
enum PanelMetrics {
    static let width: CGFloat = 360
    static let cornerRadius: CGFloat = 16
    static let inset: CGFloat = 14
    static let shadowSide: CGFloat = 24
    static let shadowBottom: CGFloat = 32
    /// The divider above the footer reaches closer to the edges than the one under the slider.
    static let footerDividerInset: CGFloat = 6
    /// The rounded highlight behind a hovered row, inset from the panel's edges.
    static let highlightInset: CGFloat = 5
    static let highlightRadius: CGFloat = 8
    /// The grey circle behind an inactive row's icon, a touch lighter than `.quaternary`.
    static let circleFill = AnyShapeStyle(.quaternary.opacity(0.85))
}

struct PanelDivider: View {
    var inset = PanelMetrics.inset

    var body: some View {
        Divider().padding(.horizontal, inset)
    }
}

/// The section headers, styled like "Output" in the Sound panel: 12 pt bold, a lighter grey than
/// `.secondary`.
struct SectionHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if let trailing { Text(trailing) }
        }
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(.secondary.opacity(0.8))
        .padding(.horizontal, PanelMetrics.inset)
        .padding(.top, 8.5)
        .padding(.bottom, 3)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// AppKit's window glass over a soft drawn shadow. SwiftUI's `glassEffect` and the window's
    /// own shadow both gave a darker edge than Control Center's.
    func panelBackground(cornerRadius: CGFloat = PanelMetrics.cornerRadius) -> some View {
        background(WindowGlass(cornerRadius: cornerRadius))
            .background(SoftShadow(cornerRadius: cornerRadius))
    }

    /// The light rounded highlight native menu rows show under the pointer.
    func hoverHighlight(_ id: String, in hover: HoverState) -> some View {
        background(
            RoundedRectangle(cornerRadius: PanelMetrics.highlightRadius, style: .continuous)
                .fill(Color.primary.opacity(hover.row == id ? 0.08 : 0))
                .padding(.horizontal, PanelMetrics.highlightInset))
        .onHover { inside in
            if inside {
                hover.row = id
            } else if hover.row == id {
                hover.row = nil
            }
        }
    }
}

/// Which panel row is under the pointer. Owned by PanelController, because SwiftUI's `@State`
/// doesn't build with only the Command Line Tools (SPEC 11).
@MainActor
@Observable
final class HoverState {
    var row: String?
}

/// Only the shadow, cut out where the panel is, so it doesn't tint the glass.
private struct SoftShadow: View {
    let cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(Color.black)
            .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
            .mask {
                Rectangle()
                    .padding(-60)
                    .overlay(shape.blendMode(.destinationOut))
                    .compositingGroup()
            }
            .accessibilityHidden(true)
    }
}

private struct WindowGlass: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.cornerRadius = cornerRadius
        return view
    }

    func updateNSView(_ view: NSGlassEffectView, context: Context) {
        view.cornerRadius = cornerRadius
    }
}
