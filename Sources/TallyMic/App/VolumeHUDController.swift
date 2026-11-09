import AppKit
import ApplicationServices
import SwiftUI

/// Shows the volume bubble (SPEC 7.7) where macOS shows its own: centered under the Sound icon in
/// the menu bar, 11 pt below the menu bar. It never takes clicks or focus.
@MainActor
final class VolumeHUDController {
    private let state = VolumeHUDState()
    private let panel: NSPanel
    private var hideTask: Task<Void, Never>?
    private static let shownFor: Duration = .milliseconds(1500)

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: VolumeHUDMetrics.width, height: VolumeHUDMetrics.height),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.contentView = NSHostingView(rootView: VolumeHUDView(state: state))
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
    }

    func show(_ volume: MonitorVolume) {
        state.volume = volume
        if !panel.isVisible || panel.alphaValue < 1 {
            panel.setFrameTopLeftPoint(Self.topLeft())
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.shownFor)
            guard !Task.isCancelled, let self else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                self.panel.animator().alphaValue = 0
            } completionHandler: { [panel = self.panel] in
                MainActor.assumeIsolated { if panel.alphaValue == 0 { panel.orderOut(nil) } }
            }
        }
    }

    /// Finds the Sound icon ahead of the first key press, which then needs only one quick check.
    func locateSoundIcon() {
        _ = MenuBarExtras.soundIcon()
    }

    /// Under the Sound icon if it's in the menu bar, else at the top right, 11 pt below the menu
    /// bar of the screen it's on.
    private static func topLeft() -> NSPoint {
        let icon = MenuBarExtras.soundIcon()
        guard let screen = icon.flatMap({ icon in NSScreen.screens.first { $0.frame.contains(NSPoint(x: icon.midX, y: icon.midY)) } })
                ?? NSScreen.main ?? NSScreen.screens.first else { return .zero }
        let frame = screen.frame
        let top = frame.maxY - MenuBarExtras.menuBarHeight(on: screen) - VolumeHUDMetrics.gap
        let centerX = icon?.midX ?? frame.maxX - 12 - VolumeHUDMetrics.width / 2
        let x = min(max(centerX - VolumeHUDMetrics.width / 2, frame.minX + 8), frame.maxX - 8 - VolumeHUDMetrics.width)
        return NSPoint(x: x, y: top)
    }
}

/// Where the system's Sound icon is in the menu bar, through the Accessibility API (which Tally
/// Mic is allowed to use once the volume keys are on).
///
/// On macOS 27 the menu bar icons belong to MenuBarAgent, and asking it for its list of icons
/// (`AXExtrasMenuBar`) comes back empty nearly every time. Asking what's at a point on screen does
/// work, so Tally Mic checks points along the menu bar from the right until it finds the icon.
/// Tested on macOS 27.2: the Sound icon (`com.apple.menuextra.sound`) answered as a 22 × 22 pt
/// item, with Wi-Fi, Control Center and the clock to its right.
@MainActor
enum MenuBarExtras {
    static let soundIdentifier = "com.apple.menuextra.sound"
    /// Its center where it was last found, in Accessibility's coordinates (top left origin).
    private static var lastFound: CGPoint?
    /// Status items sit on the right of the menu bar; no need to look further left than this.
    private static let searchWidth: CGFloat = 1600
    private static let step: CGFloat = 8

    /// The Sound icon's frame in Cocoa screen coordinates (origin bottom left), or nil if it isn't
    /// in the menu bar or Accessibility isn't allowed.
    static func soundIcon() -> NSRect? {
        guard AXIsProcessTrusted(), let primary = NSScreen.screens.first else { return nil }
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.1)
        var found = lastFound.flatMap { item(at: $0, in: systemWide) }
        if found == nil {
            let screen = NSScreen.main ?? primary
            // Accessibility measures from the top left of the primary screen.
            let y = primary.frame.maxY - screen.frame.maxY + menuBarHeight(on: screen) / 2
            var x = screen.frame.maxX - 4
            while found == nil, x > max(screen.frame.minX, screen.frame.maxX - searchWidth) {
                found = item(at: CGPoint(x: x, y: y), in: systemWide)
                x -= step
            }
            Log.debug("Sound icon: " + (found.map { "at \(Int($0.minX)),\(Int($0.minY)), \(Int($0.width)) × \(Int($0.height))" } ?? "not in the menu bar"))
        }
        guard let found else {
            lastFound = nil
            return nil
        }
        lastFound = CGPoint(x: found.midX, y: found.midY)
        return NSRect(x: found.minX, y: primary.frame.maxY - found.maxY, width: found.width, height: found.height)
    }

    /// The menu bar's height: 33 pt on a MacBook Pro with a notch, 30 on a 4K monitor at 1x.
    /// `NSStatusBar.thickness` says 22 for both, so it's measured from the visible frame.
    static func menuBarHeight(on screen: NSScreen) -> CGFloat {
        let height = screen.frame.maxY - screen.visibleFrame.maxY
        return height > 0 ? height : max(screen.safeAreaInsets.top, 24)
    }

    /// For Copy Diagnostics.
    static func report() -> String {
        guard AXIsProcessTrusted() else { return "unknown (Accessibility not allowed)" }
        return soundIcon().map { "at x \(Int($0.minX)), \(Int($0.width)) pt wide" } ?? "not found in the menu bar"
    }

    /// The Sound icon's frame if it's what's at this point, in Accessibility's coordinates.
    private static func item(at point: CGPoint, in systemWide: AXUIElement) -> CGRect? {
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element) == .success,
              let element, value(element, "AXIdentifier") as? String == soundIdentifier,
              let position = self.point(value(element, kAXPositionAttribute)),
              let size = size(value(element, kAXSizeAttribute)) else { return nil }
        return CGRect(origin: position, size: size)
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }

    private static func point(_ value: CFTypeRef?) -> CGPoint? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    private static func size(_ value: CFTypeRef?) -> CGSize? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }
}
