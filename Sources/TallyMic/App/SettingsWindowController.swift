import AppKit
import SwiftUI

/// The standard macOS Settings window with toolbar tabs (SPEC 5.5), titled with the selected tab's
/// name like the system's own Settings windows: General, Devices and Setups.
@MainActor
final class SettingsWindowController {
    private let config: ConfigStore
    private let model: AppModel
    private let deviceSettings: DeviceSettings
    private let setupSettings: SetupSettings
    private let setPreferredOrder: (Bool) -> Void
    private let setMonitorVolume: (Bool) -> Void
    private let shortcutSettings: ShortcutSettings
    private let general = GeneralSettingsState()
    private let setupsTab = SetupsTabState()
    private var window: NSWindow?

    init(config: ConfigStore, model: AppModel, deviceSettings: DeviceSettings, setupSettings: SetupSettings,
         shortcutSettings: ShortcutSettings, setPreferredOrder: @escaping (Bool) -> Void,
         setMonitorVolume: @escaping (Bool) -> Void) {
        self.config = config
        self.model = model
        self.deviceSettings = deviceSettings
        self.setupSettings = setupSettings
        self.setPreferredOrder = setPreferredOrder
        self.setMonitorVolume = setMonitorVolume
        self.shortcutSettings = shortcutSettings
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        // Tally Mic has no Dock icon, so it has to come forward for its window to get focus.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    static let generalWidth: CGFloat = 480
    static let devicesWidth: CGFloat = 720
    static let setupsWidth: CGFloat = 760
    static let shortcutsWidth: CGFloat = 560

    private func makeWindow() -> NSWindow {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.addTabViewItem(tab(
            "General", symbol: "gearshape", width: Self.generalWidth, GeneralSettingsView(config: config, state: general, model: model, setPreferredOrder: setPreferredOrder,
                                setMonitorVolume: setMonitorVolume)))
        tabs.addTabViewItem(tab(
            "Devices", symbol: "mic", width: Self.devicesWidth,
            DevicesSettingsView(model: model, settings: deviceSettings)))
        tabs.addTabViewItem(tab(
            "Setups", symbol: "rectangle.on.rectangle", width: Self.setupsWidth,
            SetupsSettingsView(model: model, settings: setupSettings, state: setupsTab)))
        tabs.addTabViewItem(tab(
            "Shortcuts", symbol: "command", width: Self.shortcutsWidth,
            ShortcutsSettingsView(model: model, settings: shortcutSettings)))

        let window = NSWindow(contentViewController: tabs)
        // White like Mail's and Maccy's, as long as the app is stamped with the real SDK version
        // (see Package.swift). Stamped "macOS 14 SDK", macOS 27 drew this window light grey.
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func tab(_ label: String, symbol: String, width: CGFloat, _ view: some View) -> NSTabViewItem {
        let hosting = NSHostingController(rootView: view.frame(width: width))
        hosting.sizingOptions = [.preferredContentSize]
        // The window takes its title from the selected tab's view controller, not the tab's label.
        // Without this the window is called "Untitled".
        hosting.title = label
        let item = NSTabViewItem(viewController: hosting)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }
}
