import AppKit
import SwiftUI

/// What the feedback bubble shows. Owned by HUDController, because SwiftUI's `@State` doesn't
/// build with only the Command Line Tools (SPEC 11).
@MainActor
@Observable
final class HUDState {
    var symbol = "mic"
    var message = ""
}

/// A small glass bubble under the menu bar icon that confirms what a keyboard shortcut did, such
/// as "Microphone Muted" (SPEC 7.6). It shows for a moment and fades. It never takes clicks or focus.
@MainActor
final class HUDController {
    private let state = HUDState()
    private let panel: NSPanel
    private var hideTask: Task<Void, Never>?
    private static let shownFor: Duration = .milliseconds(1400)

    init() {
        let hosting = NSHostingView(rootView: HUDView(state: state))
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.contentView = hosting
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
    }

    func show(symbol: String, message: String, below button: NSStatusBarButton?) {
        state.symbol = symbol
        state.message = message
        guard let view = panel.contentView else { return }
        view.layoutSubtreeIfNeeded()
        let size = view.fittingSize
        panel.setContentSize(size)
        if let button, let window = button.window, let screen = window.screen {
            let icon = window.convertToScreen(button.convert(button.bounds, to: nil))
            let visible = screen.visibleFrame
            let x = min(max(icon.midX - size.width / 2, visible.minX + 8), visible.maxX - 8 - size.width)
            panel.setFrameTopLeftPoint(NSPoint(x: x, y: min(icon.minY, visible.maxY) - 4))
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.shownFor)
            guard !Task.isCancelled, let self else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                self.panel.animator().alphaValue = 0
            } completionHandler: { [panel = self.panel] in
                MainActor.assumeIsolated { if panel.alphaValue == 0 { panel.orderOut(nil) } }
            }
        }
    }
}

private struct HUDView: View {
    let state: HUDState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: state.symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 18)
            Text(state.message)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .panelBackground(cornerRadius: 17)
        // Room for the drawn shadow.
        .padding(.horizontal, 20)
        .padding(.bottom, 26)
        .accessibilityElement(children: .combine)
    }
}
