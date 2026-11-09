import Carbon.HIToolbox

/// Global keyboard shortcuts (SPEC 7.6), through Carbon's `RegisterEventHotKey`: they work in any
/// app and need no Accessibility or Input Monitoring permission, unlike watching every key press.
@MainActor
final class HotKeyCenter {
    var onPress: ((ShortcutAction) -> Void)?

    /// While a shortcut is being recorded in Settings, none fire, so typing a shortcut that's
    /// already set records it instead of running it.
    var paused = false {
        didSet {
            guard paused != oldValue else { return }
            if paused { unregisterAll() } else { _ = register(wanted) }
        }
    }

    private var wanted: [ShortcutAction: Shortcut] = [:]
    private var registered: [UInt32: (ref: EventHotKeyRef, action: ShortcutAction)] = [:]
    private var handler: EventHandlerRef?
    private static let signature: OSType = 0x544D_6963  // 'TMic'

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var hotKey = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                MemoryLayout<EventHotKeyID>.size, nil, &hotKey)
            guard status == noErr else { return status }
            let center = Unmanaged<HotKeyCenter>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { center.pressed(hotKey.id) }
            return noErr
        }, 1, &spec, context, &handler)
        if status != noErr { Log.error("Couldn't set up keyboard shortcuts (status \(status))") }
    }

    /// Registers these shortcuts in place of any before. Returns the actions whose shortcut macOS
    /// already uses, which aren't registered. (Another app's shortcuts can't be seen.)
    @discardableResult
    func register(_ shortcuts: [ShortcutAction: Shortcut]) -> Set<ShortcutAction> {
        unregisterAll()
        wanted = shortcuts
        guard !paused else { return [] }
        var refused = Set<ShortcutAction>()
        let system = SystemShortcuts.current()
        var nextID: UInt32 = 0
        for (action, shortcut) in shortcuts.sorted(by: { $0.key.key < $1.key.key }) {
            nextID += 1
            if system.contains(shortcut) {
                refused.insert(action)
                Log.info("Shortcut \(shortcut.displayName) for \(action.key) is used by macOS, so it's not set")
                continue
            }
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                shortcut.keyCode, shortcut.modifiers, EventHotKeyID(signature: Self.signature, id: nextID),
                GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &ref)
            if status == noErr, let ref {
                registered[nextID] = (ref, action)
            } else {
                refused.insert(action)
                Log.error("Shortcut \(shortcut.displayName) for \(action.key) was refused (status \(status))")
            }
        }
        return refused
    }

    private func unregisterAll() {
        for entry in registered.values { UnregisterEventHotKey(entry.ref) }
        registered = [:]
    }

    private func pressed(_ id: UInt32) {
        guard let action = registered[id]?.action else { return }
        Log.info("Shortcut: \(action.key)")
        onPress?(action)
    }
}
