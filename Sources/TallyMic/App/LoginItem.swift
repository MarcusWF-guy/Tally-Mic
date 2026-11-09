import Foundation
import ServiceManagement

/// Launch at login, through `SMAppService.mainApp` (SPEC 9). macOS keeps the real setting;
/// config.json records the choice so the first-launch default only happens once.
@MainActor
enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    /// SPEC 9: the first time Tally Mic runs from /Applications, it turns launch at login on.
    /// Copies run from the build folder never register themselves.
    static func enableOnFirstLaunch(config: ConfigStore) {
        guard config.launchAtLogin == nil, Bundle.main.bundleURL.path.hasPrefix("/Applications/") else { return }
        set(true, config: config)
    }

    static func set(_ on: Bool, config: ConfigStore) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            Log.info("Launch at login turned \(on ? "on" : "off")")
        } catch {
            Log.error("Couldn't turn launch at login \(on ? "on" : "off"): \(error.localizedDescription)")
        }
        config.launchAtLogin = on
        config.saveOrLog()
    }
}
