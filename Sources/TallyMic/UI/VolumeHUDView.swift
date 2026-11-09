import AppKit
import SwiftUI

/// What the volume bubble shows. Owned by VolumeHUDController, because SwiftUI's `@State`
/// doesn't build with only the Command Line Tools (SPEC 11).
@MainActor
@Observable
final class VolumeHUDState {
    var volume = MonitorVolume(level: 0.5)
}

/// macOS 27's volume bubble, drawn by Tally Mic for a monitor's volume (SPEC 7.7), because macOS
/// no longer lets other apps show the real one. Measured from a 2x screenshot of the real bubble
/// at half volume, over a white window.
enum VolumeHUDMetrics {
    static let width: CGFloat = 308
    static let height: CGFloat = 64
    /// Below the menu bar.
    static let gap: CGFloat = 11
    /// Where the speaker symbol's frame starts, so its glyph's left edge lands 20.5 pt from the
    /// bubble's left edge, as in the real one. The glyph is 28.5 × 22.5 pt at half volume.
    static let iconLeading: CGFloat = 16.7
    static let iconSize: CGFloat = 26.3
    static let barLeading: CGFloat = 62.5
    static let barWidth: CGFloat = 214
    static let barHeight: CGFloat = 4
    static let segmentGap: CGFloat = 1
    /// Unlit segments are white at about half opacity: 234 over the bubble's 211.
    static let unlitOpacity: CGFloat = 0.5
}

struct VolumeHUDView: View {
    let state: VolumeHUDState
    var glass = HUDGlass.Look.standard

    var body: some View {
        ZStack(alignment: .leading) {
            Image(systemName: state.volume.symbol)
                .font(.system(size: VolumeHUDMetrics.iconSize))
                .foregroundStyle(.white)
                .offset(x: VolumeHUDMetrics.iconLeading)
            SegmentBar(lit: state.volume.litSegments)
                .frame(width: VolumeHUDMetrics.barWidth, height: VolumeHUDMetrics.barHeight)
                .offset(x: VolumeHUDMetrics.barLeading)
        }
        .frame(width: VolumeHUDMetrics.width, height: VolumeHUDMetrics.height, alignment: .leading)
        .background(HUDGlass(look: glass))
        .clipShape(Capsule())
        // The real bubble's 1 px rim: darker where it turns at the ends, lighter along the top and bottom.
        .overlay(Capsule().strokeBorder(LinearGradient(
            stops: [.init(color: .white.opacity(0.22), location: 0), .init(color: .black.opacity(0.3), location: 0.3),
                    .init(color: .black.opacity(0.3), location: 0.7), .init(color: .white.opacity(0.22), location: 1)],
            startPoint: .top, endPoint: .bottom), lineWidth: 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.volume.muted ? "Volume muted" : "Volume \(Int((state.volume.level * 100).rounded())) percent")
    }
}

/// Sixteen segments with rounded ends at the far left and right, like the real bubble's bar.
/// With 32 steps, every other step leaves a segment half lit.
private struct SegmentBar: View {
    let lit: Double

    var body: some View {
        Canvas { context, size in
            let count = Int(MonitorVolume.segments)
            let gap = VolumeHUDMetrics.segmentGap
            let width = (size.width - gap * CGFloat(count - 1)) / CGFloat(count)
            context.clip(to: Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2))
            for index in 0..<count {
                let rect = CGRect(x: CGFloat(index) * (width + gap), y: 0, width: width, height: size.height)
                let fill = min(max(lit - Double(index), 0), 1)
                if fill < 1 {
                    context.fill(Path(rect), with: .color(.white.opacity(VolumeHUDMetrics.unlitOpacity)))
                }
                if fill > 0 {
                    context.fill(Path(CGRect(x: rect.minX, y: 0, width: rect.width * fill, height: size.height)), with: .color(.white))
                }
            }
        }
    }
}

/// The bubble's Liquid Glass.
struct HUDGlass: NSViewRepresentable {
    struct Look {
        var clear = false
        var tint: NSColor?

        /// Clear glass darkened a little: 211 over a white window, like the real bubble.
        /// (Regular glass came out 245.)
        static let standard = Look(clear: true, tint: NSColor.black.withAlphaComponent(0.18))
    }

    let look: Look

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        update(view)
        return view
    }

    func updateNSView(_ view: NSGlassEffectView, context: Context) {
        update(view)
    }

    private func update(_ view: NSGlassEffectView) {
        view.cornerRadius = VolumeHUDMetrics.height / 2
        view.style = look.clear ? .clear : .regular
        view.tintColor = look.tint
    }
}
