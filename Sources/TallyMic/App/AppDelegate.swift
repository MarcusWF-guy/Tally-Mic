import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var audio: AudioSystem?
    private var displays: DisplayMonitor?
    private var lid: LidMonitor?
    private var autoSwitch: AutoSwitchController?
    private var shortcuts: ShortcutSettings?
    private var hud: HUDController?
    private var monitorVolume: MonitorVolumeController?
    private var settingsWindow: SettingsWindowController?
    private var statusItem: StatusItemController?
    private var panel: PanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.info("Tally Mic \(Bundle.main.versionDescription) started on macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")

        let config = ConfigStore()
        let audio = AudioSystem(model: model, config: config)
        let displays = DisplayMonitor(model: model, config: config)
        let lid = LidMonitor()
        let autoSwitch = AutoSwitchController(model: model, audio: audio, config: config, displays: displays, lid: lid)
        let shortcuts = ShortcutSettings(config: config, model: model, hotKeys: HotKeyCenter())
        let hud = HUDController()
        let monitorVolume = MonitorVolumeController(model: model, config: config)
        audio.onOutputChange.append { monitorVolume.outputChanged() }
        LoginItem.enableOnFirstLaunch(config: config)

        let settingsWindow = SettingsWindowController(
            config: config, model: model, deviceSettings: DeviceSettings(config: config, model: model),
            setupSettings: SetupSettings(config: config, model: model), shortcutSettings: shortcuts,
            setPreferredOrder: { autoSwitch.setEnabled($0) },
            setMonitorVolume: { monitorVolume.setEnabled($0) })
        let showSettings = {
            settingsWindow.show()
            monitorVolume.recheckAccess()
        }
        let panel = PanelController(
            model: model,
            actions: PanelActions(
                select: { autoSwitch.panelPicked($0) },
                setAutoSwitching: { autoSwitch.setEnabled($0) },
                setMuted: { audio.setMuted($0) },
                setVolume: { audio.setVolume($0) },
                openTallySettings: showSettings,
                openSoundSettings: SoundSettings.open))
        let statusItem = StatusItemController(model: model)
        statusItem.onLeftClick = { button in panel.toggle(below: button) }
        statusItem.onExpand = { button in
            if panel.justClosed {
                statusItem.panelDidClose()  // The click that just closed it; stay closed.
            } else {
                panel.open(below: button)
            }
        }
        statusItem.onCollapse = { panel.close() }
        statusItem.onMenuOpen = { panel.close() }
        statusItem.onSettings = showSettings
        panel.onVisibilityChange = { isOpen in
            if !isOpen { statusItem.panelDidClose() }
        }

        // SPEC 7.6: what each shortcut does, confirmed with a bubble under the icon.
        let model = model
        shortcuts.hotKeys.onPress = { action in
            let say = { (symbol: String, message: String) in hud.show(symbol: symbol, message: message, below: statusItem.button) }
            switch action {
            case .toggleMute:
                let mute = !model.isMuted
                if audio.setMuted(mute) {
                    say(mute ? "mic.slash.fill" : "mic.fill", mute ? "Microphone Muted" : "Microphone On")
                } else {
                    say("exclamationmark.triangle", "\(model.currentInput.map(model.shownName) ?? "This microphone") Can't Be Muted")
                }
            case .toggleAutoSwitching:
                let on = !model.preferredOrderEnabled
                autoSwitch.setEnabled(on, reason: "shortcut")
                say("arrow.triangle.2.circlepath", on ? "Automatic Switching On" : "Automatic Switching Off")
            case .openMenu:
                if let button = statusItem.button { panel.toggle(below: button) }
            case .selectInput(let uid):
                let name = model.knownDevices.first { $0.uid == uid }?.shownName ?? "That Microphone"
                if let device = model.inputs.first(where: { $0.uid == uid }) {
                    autoSwitch.panelPicked(device, via: "a shortcut")
                    say(device.symbol, model.shownName(of: device))
                } else {
                    say("exclamationmark.triangle", "\(name) Isn't Connected")
                }
            }
        }

        self.audio = audio
        self.displays = displays
        self.lid = lid
        self.autoSwitch = autoSwitch
        self.shortcuts = shortcuts
        self.hud = hud
        self.monitorVolume = monitorVolume
        self.settingsWindow = settingsWindow
        self.panel = panel
        self.statusItem = statusItem
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.info("Tally Mic quit")
    }
}
