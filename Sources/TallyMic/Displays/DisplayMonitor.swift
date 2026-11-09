import AppKit

/// Which external displays are connected (SPEC 6.1, 7.4), kept in AppModel as they come and go,
/// for working out the active setup. The Mac's own screen never counts: it's there in every setup.
@MainActor
final class DisplayMonitor {
    private let model: AppModel
    private let config: ConfigStore
    private var observer: NSObjectProtocol?
    private var lastSetupID: String?
    /// An external display connected or disconnected, for automatic switching (SPEC 6.2).
    var onChange: (() -> Void)?

    init(model: AppModel, config: ConfigStore) {
        self.model = model
        self.config = config
        model.setups = config.setups
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
        trackChanges { [weak self] in self?.logActiveSetup() }
    }

    private func refresh() {
        let connected = Self.connectedExternalDisplays()
        let old = model.displays
        for display in connected where !old.contains(display) { Log.info("Display connected: \(display.name)") }
        for display in old where !connected.contains(display) { Log.info("Display disconnected: \(display.name)") }
        let changed = connected != old
        model.displays = connected
        if config.recordDisplays(connected) { config.saveOrLog() }
        model.knownDisplays = config.displays
        if changed { onChange?() }
    }

    private func logActiveSetup() {
        let setup = model.activeSetup
        guard setup.id != lastSetupID else { return }
        lastSetupID = setup.id
        let reason = setup.trigger.map { "\($0.name) is connected" } ?? "no other setup's display is connected"
        Log.info("Active setup: \(setup.name) (\(reason))")
    }

    /// The external displays connected now. Names come from NSScreen; a display without a screen
    /// (mirrored, say) is named by its model number.
    static func connectedExternalDisplays() -> [DisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { return [] }
        let names = Dictionary(NSScreen.screens.compactMap { screen -> (CGDirectDisplayID, String)? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return (number.uint32Value, screen.localizedName)
        }, uniquingKeysWith: { first, _ in first })
        return ids.prefix(Int(count))
            .filter { CGDisplayIsBuiltin($0) == 0 }
            .map { id in
                DisplayID(name: names[id] ?? "Display \(CGDisplayModelNumber(id))",
                          vendorID: CGDisplayVendorNumber(id), modelID: CGDisplayModelNumber(id),
                          serial: CGDisplaySerialNumber(id))
            }
    }
}
