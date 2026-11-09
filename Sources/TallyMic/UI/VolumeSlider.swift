import SwiftUI

/// The input volume slider (SPEC 5.3), styled like the Sound panel's: a quiet icon on the left, a
/// loud one on the right, no label or number. The icons are the mic with a level meter that System
/// Settings uses for input volume, empty on the left and full on the right. When the current input
/// has no volume Tally Mic can set, it shows a greyed track with no knob, like the Sound panel does
/// for an output without one.
struct VolumeSlider: View {
    /// 0 to 1, or nil when the volume can't be set.
    let volume: Float?
    let deviceName: String?
    let onChange: (Float) -> Void

    var body: some View {
        HStack(spacing: 4) {
            icon(level: 0)
            VolumeTrack(volume: volume, deviceName: deviceName, onChange: onChange)
            icon(level: 1)
        }
        // Lighter when there's nothing to adjust, matching the Sound panel's disabled icons.
        .foregroundStyle(volume == nil ? AnyShapeStyle(.secondary.opacity(0.45)) : AnyShapeStyle(.secondary))
        .help(volume == nil ? "This microphone has no volume macOS can change" : "")
    }

    private func icon(level: Double) -> some View {
        Image(systemName: "mic.and.signal.meter.fill", variableValue: level)
            .font(.system(size: 13))
            .frame(width: 17)
            .accessibilityHidden(true)
    }
}

/// The track and knob, drawn to the Sound panel's measurements rather than using SwiftUI's
/// `Slider`: in a panel on macOS 27 that draws a 4 pt track and a round knob, and lays out taller on
/// screen than offscreen. The Sound panel's has a 6 pt track and a 20 by 16 pt white pill for a knob.
struct VolumeTrack: View {
    let volume: Float?
    let deviceName: String?
    let onChange: (Float) -> Void

    static let trackHeight: CGFloat = 6
    static let knobSize = CGSize(width: 20, height: 16)

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            // The knob stays on the track: its center travels from one half-knob in to the other.
            let travel = max(width - Self.knobSize.width, 1)
            let knobX = Self.knobSize.width / 2 + travel * CGFloat(volume ?? 0)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(volume == nil ? AnyShapeStyle(Color.primary.opacity(0.12)) : AnyShapeStyle(.quaternary))
                    .frame(height: Self.trackHeight)
                if volume != nil {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: knobX, height: Self.trackHeight)
                    Capsule()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.22), radius: 1.5, y: 0.5)
                        .frame(width: Self.knobSize.width, height: Self.knobSize.height)
                        .offset(x: knobX - Self.knobSize.width / 2)
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            // Pressing anywhere on the track jumps there, then dragging follows the pointer.
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                guard volume != nil else { return }
                let value = (drag.location.x - Self.knobSize.width / 2) / travel
                onChange(Float(min(max(value, 0), 1)))
            })
        }
        .frame(height: Self.knobSize.height)
        .accessibilityElement()
        .accessibilityLabel("Input volume")
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            guard let volume else { return }
            let step: Float = direction == .increment ? 0.05 : -0.05
            onChange(min(max(volume + step, 0), 1))
        }
    }

    private var accessibilityValue: String {
        if let volume { return "\(Int((volume * 100).rounded()))%" }
        return deviceName.map { "Not adjustable for \($0)" } ?? "Not adjustable"
    }
}
