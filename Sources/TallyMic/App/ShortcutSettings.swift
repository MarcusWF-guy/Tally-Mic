import Foundation

/// The Shortcuts tab's changes (SPEC 7.6): each is saved and registered at once. A shortcut can
/// only do one thing, so giving it to an action takes it from any other.
@MainActor
final class ShortcutSettings {
    let hotKeys: HotKeyCenter
    private let config: ConfigStore
    private let model: AppModel

    init(config: ConfigStore, model: AppModel, hotKeys: HotKeyCenter) {
        self.config = config
        self.model = model
        self.hotKeys = hotKeys
        apply(config.shortcuts)
    }

    func set(_ shortcut: Shortcut?, for action: ShortcutAction) {
        let shortcuts = Self.assigning(shortcut, to: action, in: model.shortcuts)
        Log.info("Shortcuts: \(action.key) is " + (shortcut.map { $0.displayName } ?? "cleared"))
        config.setShortcuts(shortcuts)
        config.saveOrLog()
        apply(shortcuts)
    }

    /// Gives `shortcut` to `action` (nil clears it), taking it from any other action that had it.
    nonisolated static func assigning(_ shortcut: Shortcut?, to action: ShortcutAction,
                                      in shortcuts: [ShortcutAction: Shortcut]) -> [ShortcutAction: Shortcut] {
        var result = shortcuts.filter { $0.key == action || $0.value != shortcut }
        result[action] = shortcut
        return result
    }

    /// While recording, no shortcut fires (see HotKeyCenter.paused).
    func setRecording(_ recording: Bool) {
        hotKeys.paused = recording
        if !recording { model.refusedShortcuts = hotKeys.register(model.shortcuts) }
    }

    private func apply(_ shortcuts: [ShortcutAction: Shortcut]) {
        model.shortcuts = shortcuts
        model.refusedShortcuts = hotKeys.register(shortcuts)
    }
}
