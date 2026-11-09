import AppKit
import SwiftUI

/// The drop-down panel (SPEC 5.2), copied from Tally Cam. A borderless, non-activating panel,
/// so the app you're in stays active while it's open. It stays put across desktops and shows
/// over full-screen apps.
@MainActor
final class PanelController {
    var onVisibilityChange: ((Bool) -> Void)?

    private let panel: TallyPanel
    private let hover = HoverState()
    private var outsideClickMonitor: Any?
    private var shadowClickMonitor: Any?

    init(model: AppModel, actions: PanelActions) {
        // With .preferredContentSize, AppKit resizes the window as the content grows and shrinks,
        // such as when a mic is plugged in. TallyPanel.setFrame keeps the top edge where it is.
        // Both footer buttons open a window, so they close the panel first.
        var close: () -> Void = {}
        var actions = actions
        let openTallySettings = actions.openTallySettings
        let openSoundSettings = actions.openSoundSettings
        actions.openTallySettings = {
            close()
            openTallySettings()
        }
        actions.openSoundSettings = {
            close()
            openSoundSettings()
        }
        let hosting = NSHostingController(rootView: PanelView(model: model, actions: actions, hover: hover))
        hosting.sizingOptions = [.preferredContentSize]
        panel = TallyPanel(contentViewController: hosting)
        panel.onEscape = { [weak self] in self?.close() }
        close = { [weak self] in self?.close() }
    }

    /// Not the window's visibility, which stays true while the panel fades out.
    private(set) var isOpen = false
    private var openedAt = ContinuousClock.now - .seconds(60)
    private var closedAt = ContinuousClock.now - .seconds(60)

    /// True right after the panel closed. A click on the menu bar icon closes the panel as an outside
    /// click; if the menu bar then starts a new session for the same click, the panel stays closed.
    var justClosed: Bool { ContinuousClock.now - closedAt < .milliseconds(300) }

    func toggle(below button: NSStatusBarButton) {
        isOpen ? close() : open(below: button)
    }

    func open(below button: NSStatusBarButton) {
        guard !isOpen, let buttonWindow = button.window, let screen = buttonWindow.screen else { return }
        isOpen = true
        openedAt = .now
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))

        panel.contentViewController?.view.layoutSubtreeIfNeeded()
        let size = panel.contentViewController?.view.fittingSize ?? panel.frame.size
        // The window is wider than the visible panel by the shadow's room on each side.
        let panelWidth = size.width - 2 * PanelMetrics.shadowSide
        let origin = PanelPlacement.topLeft(below: buttonFrame, panelWidth: panelWidth, in: screen.visibleFrame)

        panel.anchorTop = origin.y
        panel.setContentSize(size)
        panel.setFrameTopLeftPoint(NSPoint(x: origin.x - PanelMetrics.shadowSide, y: origin.y))
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }

        // Clicks in other apps close the panel. Mouse monitors don't need Accessibility permission.
        // On macOS 27 a click on Tally Mic's own menu bar icon arrives here too, because the menu
        // bar handles it, so this also closes the panel on a second click on the icon. The click
        // that opened the panel can arrive a moment after it opened, so that one is ignored.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, ContinuousClock.now - self.openedAt > .milliseconds(200) else { return }
                self.close()
            }
        }
        // The shadow's room is part of Tally Mic's window, so clicks there never reach the global
        // monitor above. Treat them as outside clicks too.
        shadowClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] event in
            let handled = MainActor.assumeIsolated { self?.closeIfInShadow(event) ?? false }
            return handled ? nil : event
        }
        onVisibilityChange?(true)
        // Whether it became the key window: if not, dark mode draws its switches grey while on
        // (Milestone 4's dark mode check). Read a moment later, once macOS has decided.
        Task { @MainActor [panel] in
            Log.debug("Panel opened at \(NSStringFromRect(panel.frame)), key window: \(panel.isKeyWindow)")
        }
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        closedAt = .now
        for monitor in [outsideClickMonitor, shadowClickMonitor].compactMap({ $0 }) {
            NSEvent.removeMonitor(monitor)
        }
        outsideClickMonitor = nil
        shadowClickMonitor = nil
        // The pointer can leave with the panel, so no row says it was left. Start fresh next time.
        hover.row = nil
        onVisibilityChange?(false)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self, panel] in
            // Unless it was opened again during the fade.
            MainActor.assumeIsolated { if self?.isOpen != true { panel.orderOut(nil) } }
        }
    }

    private func closeIfInShadow(_ event: NSEvent) -> Bool {
        guard event.window === panel else { return false }
        let visiblePanel = NSRect(
            x: PanelMetrics.shadowSide,
            y: PanelMetrics.shadowBottom,
            width: panel.frame.width - 2 * PanelMetrics.shadowSide,
            height: panel.frame.height - PanelMetrics.shadowBottom)
        guard !visiblePanel.contains(event.locationInWindow) else { return false }
        close()
        return true
    }
}

final class TallyPanel: NSPanel {
    /// Where the top edge stays when the content grows or shrinks, like a menu dropping down.
    var anchorTop: CGFloat?
    var onEscape: (() -> Void)?

    init(contentViewController: NSViewController) {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.contentViewController = contentViewController
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isMovable = false
        backgroundColor = .clear
        isOpaque = false
        // The panel draws its own softer shadow; the window's made the edge too dark.
        hasShadow = false
        animationBehavior = .none
    }

    // Becoming key lets Esc reach the panel. Because it's non-activating, the app behind stays active.
    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53 {
            onEscape?()
            return
        }
        super.sendEvent(event)
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var frame = frameRect
        if let anchorTop {
            frame.origin.y = anchorTop - frame.height
        }
        super.setFrame(frame, display: flag)
    }
}

/// Pure placement math, kept apart so it can be tested. Matched to Control Center's Wi-Fi and
/// Sound panels on macOS 27.2: 1 pt below the menu bar, right edge level with the icon's.
enum PanelPlacement {
    static let gapBelowMenuBar: CGFloat = 1
    static let screenMargin: CGFloat = 8

    static func topLeft(below button: NSRect, panelWidth: CGFloat, in visible: NSRect) -> NSPoint {
        let alignedRight = button.maxX - panelWidth
        let x = min(max(alignedRight, visible.minX + screenMargin), visible.maxX - screenMargin - panelWidth)
        return NSPoint(x: x, y: min(button.minY, visible.maxY) - gapBelowMenuBar)
    }
}
