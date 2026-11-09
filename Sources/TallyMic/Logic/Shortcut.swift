import Carbon.HIToolbox
import Foundation

/// A global keyboard shortcut (SPEC 7.6): a key and its modifiers, in Carbon's terms because
/// that's what `RegisterEventHotKey` takes.
struct Shortcut: Equatable, Hashable, Sendable {
    var keyCode: UInt32
    /// Carbon modifier flags: `cmdKey`, `optionKey`, `controlKey`, `shiftKey`.
    var modifiers: UInt32

    static let modifierSymbols: [(flag: Int, symbol: String)] = [
        (controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘"),
    ]

    /// As macOS writes shortcuts in menus: modifiers in the order ⌃⌥⇧⌘, then the key.
    @MainActor
    var displayName: String {
        Self.modifierSymbols.filter { modifiers & UInt32($0.flag) != 0 }.map(\.symbol).joined() + KeyNames.name(for: keyCode)
    }

    /// Function keys work on their own; anything else needs ⌘, ⌥ or ⌃, so typing never triggers one.
    static func isAllowed(keyCode: UInt32, modifiers: UInt32) -> Bool {
        KeyNames.isFunctionKey(keyCode) || modifiers & UInt32(cmdKey | optionKey | controlKey) != 0
    }
}

/// The shortcuts macOS itself uses and has turned on (System Settings > Keyboard > Keyboard
/// Shortcuts), like ⌘Space for Spotlight. macOS lets an app register the same keys anyway, and
/// then they clash, so Tally Mic checks this list first (SPEC 7.6).
enum SystemShortcuts {
    static func current() -> Set<Shortcut> {
        var list: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&list) == noErr,
              let entries = list?.takeRetainedValue() as? [[String: Any]] else { return [] }
        return parse(entries)
    }

    /// Keeps the turned-on entries, with only the ⌘⌥⌃⇧ modifier bits (macOS adds others, like Fn).
    static func parse(_ entries: [[String: Any]]) -> Set<Shortcut> {
        let mask = UInt32(cmdKey | optionKey | controlKey | shiftKey)
        return Set(entries.compactMap { entry -> Shortcut? in
            guard entry[kHISymbolicHotKeyEnabled as String] as? Bool == true,
                  let code = (entry[kHISymbolicHotKeyCode as String] as? Int).flatMap(UInt32.init(exactly:)),
                  let modifiers = (entry[kHISymbolicHotKeyModifiers as String] as? Int).flatMap(UInt32.init(exactly:))
            else { return nil }
            return Shortcut(keyCode: code, modifiers: modifiers & mask)
        })
    }
}

/// What a shortcut does (SPEC 7.6). The key is how config.json stores it.
enum ShortcutAction: Hashable, Sendable {
    case toggleMute
    case toggleAutoSwitching
    case openMenu
    case selectInput(uid: String)

    var key: String {
        switch self {
        case .toggleMute: "toggleMute"
        case .toggleAutoSwitching: "toggleAutoSwitching"
        case .openMenu: "openMenu"
        case .selectInput(let uid): "input:" + uid
        }
    }

    init?(key: String) {
        switch key {
        case "toggleMute": self = .toggleMute
        case "toggleAutoSwitching": self = .toggleAutoSwitching
        case "openMenu": self = .openMenu
        default:
            guard key.hasPrefix("input:"), key.count > 6 else { return nil }
            self = .selectInput(uid: String(key.dropFirst(6)))
        }
    }
}

/// The names keys go by in shortcuts: symbols for the special keys, and for the rest, what the
/// key types on the current keyboard layout.
enum KeyNames {
    static let special: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫", kVK_Escape: "⎋",
        kVK_ForwardDelete: "⌦", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑",
        kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]

    static func isFunctionKey(_ keyCode: UInt32) -> Bool {
        special[Int(keyCode)]?.hasPrefix("F") == true && special[Int(keyCode)]!.count > 1
    }

    @MainActor
    static func name(for keyCode: UInt32) -> String {
        if let name = special[Int(keyCode)] { return name }
        return typed(by: keyCode)?.uppercased() ?? "Key \(keyCode)"
    }

    /// What the key types with no modifiers on the current ASCII-capable layout.
    @MainActor
    private static func typed(by keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, characters.count, &length, &characters)
        }
        guard status == noErr, length > 0 else { return nil }
        let text = String(utf16CodeUnits: characters, count: length).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
