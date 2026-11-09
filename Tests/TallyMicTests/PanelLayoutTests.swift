import AppKit
import SwiftUI
import Testing
@testable import TallyMic

/// Lays the panel out offscreen with a typical set of inputs. Set TALLY_SNAPSHOT_DIR to also save a PNG of
/// each, for checking the layout without opening the app. The glass doesn't draw offscreen, so the
/// picture has a plain background.
@Suite("Panel layout")
@MainActor
struct PanelLayoutTests {
    private func model(volume: Float?) -> AppModel {
        let model = AppModel()
        model.inputs = [
            InputDevice(objectID: 99, uid: "headset", name: "Wireless Headset Receiver",
                        transport: .usb, transportCode: 0),
            InputDevice(objectID: 115, uid: "webcam", name: "USB Webcam", transport: .usb, transportCode: 0),
            InputDevice(objectID: 94, uid: "builtin", name: "MacBook Pro Microphone", transport: .builtIn, transportCode: 0),
            InputDevice(objectID: 77, uid: "teams", name: "Microsoft Teams Audio", transport: .virtual, transportCode: 0),
            InputDevice(objectID: 111, uid: "usbMic", name: "USB Microphone", transport: .usb, transportCode: 0),
        ]
        model.currentInputID = 115
        model.volume = volume
        return model
    }

    private func render(_ model: AppModel, named name: String) -> NSSize {
        let actions = PanelActions(
            select: { _ in }, setAutoSwitching: { _ in }, setMuted: { _ in }, setVolume: { _ in },
            openTallySettings: {}, openSoundSettings: {})
        let view = NSHostingView(rootView: PanelView(model: model, actions: actions, hover: HoverState())
            .background(Color(nsColor: .windowBackgroundColor)))
        let size = view.fittingSize
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        save(view, named: name)
        return size
    }

    private func save(_ view: NSView, named name: String) {
        guard let folder = ProcessInfo.processInfo.environment["TALLY_SNAPSHOT_DIR"],
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let url = URL(fileURLWithPath: folder).appendingPathComponent("\(name).png")
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }

    @Test func matchesTheSoundMenusWidth() {
        let size = render(model(volume: 0.37), named: "panel")
        #expect(size.width == PanelMetrics.width + 2 * PanelMetrics.shadowSide)
        #expect(size.height > 250 && size.height < 450)
    }

    /// The greyed track takes the slider's place, so the panel doesn't change height.
    @Test func keepsItsHeightWithoutAVolume() {
        let withVolume = render(model(volume: 0.37), named: "panel")
        let without = render(model(volume: nil), named: "panel-no-volume")
        #expect(withVolume == without)
    }

    /// Settings > General, saved as settings-general.png with TALLY_SNAPSHOT_DIR.
    @Test func laysOutSettings() {
        let config = ConfigStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("tally-mic-tests-\(UUID().uuidString)/config.json"))
        let view = NSHostingView(rootView: GeneralSettingsView(config: config, state: GeneralSettingsState(), model: AppModel(), setPreferredOrder: { _ in }, setMonitorVolume: { _ in })
            .frame(width: SettingsWindowController.generalWidth)
            .background(Color(nsColor: .windowBackgroundColor)))
        let size = view.fittingSize
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        save(view, named: "settings-general")
        #expect(size.width == SettingsWindowController.generalWidth)
        #expect(size.height > 150 && size.height < 650)
    }

    /// Settings > Devices, saved as settings-devices.png with TALLY_SNAPSHOT_DIR.
    @Test func laysOutDevices() {
        let config = ConfigStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("tally-mic-tests-\(UUID().uuidString)/config.json"))
        let model = model(volume: 0.37)
        config.recordSeen(model.inputs)
        config.recordSeen([InputDevice(objectID: 1, uid: "airpods", name: "User's AirPods Pro", transport: .bluetooth, transportCode: 0)])
        config.setDisplayName("Headset", uid: "headset")
        config.setVisible(false, uid: "teams")
        model.knownDevices = config.devices
        let view = NSHostingView(rootView: DevicesSettingsView(model: model, settings: DeviceSettings(config: config, model: model))
            .frame(width: SettingsWindowController.devicesWidth)
            .background(Color(nsColor: .windowBackgroundColor)))
        let size = view.fittingSize
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        save(view, named: "settings-devices")
        #expect(size.width == SettingsWindowController.devicesWidth)
    }

    @Test func showsAnEmptyState() {
        let empty = AppModel()
        let size = render(empty, named: "panel-empty")
        #expect(size.width == PanelMetrics.width + 2 * PanelMetrics.shadowSide)
    }
}
