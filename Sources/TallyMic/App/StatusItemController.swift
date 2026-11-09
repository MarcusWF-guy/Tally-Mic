import AppKit

/// The menu bar icon (SPEC 5.1). Left click toggles the panel; right click shows a small menu.
///
/// On macOS 27 the panel is the icon's "expanded interface": the menu bar opens a session on a left
/// click and keeps the icon highlighted until the session ends, like the Sound icon. Before macOS 27
/// a left click arrives as the button's action instead.
@MainActor
final class StatusItemController: NSObject {
    /// Before macOS 27: a left click, to toggle the panel.
    var onLeftClick: ((NSStatusBarButton) -> Void)?
    /// macOS 27: the menu bar began a session, so the panel should open below the button.
    var onExpand: ((NSStatusBarButton) -> Void)?
    /// macOS 27: the menu bar ended the session (Esc, for one), so the panel should close.
    var onCollapse: (() -> Void)?
    /// Right click, just before the menu opens. The panel closes, like one menu replacing another.
    var onMenuOpen: (() -> Void)?
    var onSettings: (() -> Void)?

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    /// For placing the panel and the shortcut bubble under the icon.
    var button: NSStatusBarButton? { item.button }
    private let model: AppModel
    /// A right click opens the menu, and on macOS 27 the menu bar runs the menu as a session, which
    /// arrives like a panel session. These let `statusItem(_:didBegin:)` tell it apart.
    private var menuIsOpen = false
    private var lastRightClick = ContinuousClock.now - .seconds(60)

    init(model: AppModel) {
        self.model = model
        super.init()

        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(clicked(_:))
        // On macOS 27, with the delegate set, left clicks go to the session instead (tested with
        // Marcus); right clicks still arrive here.
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        button.setAccessibilityLabel("Tally Mic")
        item.expandedInterfaceDelegate = self

        trackChanges { [weak self] in self?.update() }
    }

    /// The panel closed by itself: an outside click, a click on this icon, Esc, or a footer button.
    /// A click on the icon while the panel is open reaches Tally Mic only as an outside click, so
    /// this is also how a second click on the icon closes the panel. The menu bar has to be told,
    /// or the icon stays highlighted.
    func panelDidClose() {
        item.expandedInterfaceSession?.cancel()
    }

    /// SPEC 5.1: `mic`, filled while any app is recording, like Tally Cam's camera icon, and
    /// crossed out while muted (SPEC 7.5).
    private func update() {
        let inUse = model.micInUse
        let muted = model.effectivelyMuted
        let symbol = (muted ? "mic.slash" : "mic") + (inUse ? ".fill" : "")
        let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: "Tally Mic")
        icon?.isTemplate = true
        item.button?.image = icon
        let input = model.currentInput?.name
        item.button?.setAccessibilityValue(
            [input, muted ? "Muted" : nil, inUse ? "In use" : nil].compactMap { $0 }.joined(separator: ", "))
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseDown {
            Log.debug("Right click: showing the menu")
            lastRightClick = .now
            onMenuOpen?()
            showMenu()
        } else {
            onLeftClick?(sender)
        }
    }

    @objc private func openSettings() {
        onSettings?()
    }

    /// SPEC 5.1: shown as the status item's own menu, so macOS places and styles it like every
    /// other menu bar menu. Popping it up from the button instead gave it the menu bar's dark,
    /// translucent look and put it in the wrong place.
    private func showMenu() {
        menuIsOpen = true
        item.menu = makeMenu()
        item.button?.performClick(nil)  // Returns once the menu closes.
        item.menu = nil  // Otherwise left clicks would open the menu instead of the panel.
        menuIsOpen = false
        // A session the right click started after the menu closed is ignored too (see didBegin).
        lastRightClick = .now
        // One that began before the menu opened (the menu bar's own reaction to the click) ends
        // here, along with the panel it opened.
        if item.expandedInterfaceSession != nil {
            Log.debug("Menu closed: ending the panel session the right click started")
            onMenuOpen?()
            item.expandedInterfaceSession?.cancel()
        }
    }

    /// True when a menu bar session belongs to a right click rather than a left one.
    private var sessionIsFromRightClick: Bool {
        menuIsOpen
            || ContinuousClock.now - lastRightClick < .milliseconds(500)
            || NSEvent.pressedMouseButtons & 0b10 != 0
    }

    /// No keyboard shortcuts and no icons, like the menus of Apple's own menu bar icons.
    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let settings = menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Tally Mic", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        for item in menu.items { item.preferredImageVisibility = .hidden }
        return menu
    }
}

extension StatusItemController: @preconcurrency NSStatusItemExpandedInterfaceDelegate {
    func statusItem(_ statusItem: NSStatusItem, didBegin session: NSStatusItemExpandedInterfaceSession) {
        // A right click shows the menu, not the panel (found by Marcus: it opened both). The menu
        // bar runs the menu as a session too, and cancelling it closes the menu, so it's left alone
        // to end when the menu closes.
        if sessionIsFromRightClick {
            Log.debug("Menu bar session began for the right-click menu: no panel")
            return
        }
        Log.debug("Menu bar session began")
        guard let button = statusItem.button else {
            session.cancel()
            return
        }
        onExpand?(button)
    }

    func statusItemDidEndExpandedInterfaceSession(_ statusItem: NSStatusItem, animated: Bool) {
        Log.debug("Menu bar session ended")
        onCollapse?()
    }
}
