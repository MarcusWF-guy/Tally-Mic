import Carbon.HIToolbox
import Foundation
import Testing
@testable import TallyMic

@Suite("Keyboard shortcuts")
@MainActor
struct ShortcutTests {
    private let cmdOption = UInt32(cmdKey | optionKey)

    @Test func namesLikeMacOSMenus() {
        #expect(Shortcut(keyCode: UInt32(kVK_F5), modifiers: 0).displayName == "F5")
        #expect(Shortcut(keyCode: UInt32(kVK_F5), modifiers: cmdOption).displayName == "⌥⌘F5")
        #expect(Shortcut(keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(controlKey | shiftKey | cmdKey)).displayName == "⌃⇧⌘M")
        #expect(Shortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)).displayName == "⌥Space")
    }

    /// Typing must never trigger one: plain keys and Shift-only need ⌘, ⌥ or ⌃. F-keys work alone.
    @Test func needsAModifierUnlessItsAFunctionKey() {
        #expect(!Shortcut.isAllowed(keyCode: UInt32(kVK_ANSI_M), modifiers: 0))
        #expect(!Shortcut.isAllowed(keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(shiftKey)))
        #expect(Shortcut.isAllowed(keyCode: UInt32(kVK_ANSI_M), modifiers: cmdOption))
        #expect(Shortcut.isAllowed(keyCode: UInt32(kVK_F13), modifiers: 0))
        #expect(!Shortcut.isAllowed(keyCode: UInt32(kVK_Escape), modifiers: 0))
    }

    /// macOS's own shortcuts, as `CopySymbolicHotKeys` gives them: only turned-on ones count, and
    /// extra modifier bits like Fn (0x20000) are dropped.
    @Test func readsMacOSShortcuts() {
        let entries: [[String: Any]] = [
            [kHISymbolicHotKeyCode as String: kVK_Space, kHISymbolicHotKeyModifiers as String: cmdKey,
             kHISymbolicHotKeyEnabled as String: true],
            [kHISymbolicHotKeyCode as String: kVK_F1, kHISymbolicHotKeyModifiers as String: controlKey | 0x20000,
             kHISymbolicHotKeyEnabled as String: true],
            [kHISymbolicHotKeyCode as String: kVK_ANSI_M, kHISymbolicHotKeyModifiers as String: controlKey | optionKey,
             kHISymbolicHotKeyEnabled as String: false],
            [kHISymbolicHotKeyCode as String: -1, kHISymbolicHotKeyModifiers as String: 0,
             kHISymbolicHotKeyEnabled as String: true],
        ]
        #expect(SystemShortcuts.parse(entries) == [
            Shortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey)),
            Shortcut(keyCode: UInt32(kVK_F1), modifiers: UInt32(controlKey)),
        ])
    }

    @Test func actionKeysRoundTrip() {
        let headset = "AppleUSBAudioEngine:Unknown Manufacturer:Wireless Headset Receiver:0123456789abcdef:1"
        for action in [ShortcutAction.toggleMute, .toggleAutoSwitching, .openMenu, .selectInput(uid: headset)] {
            #expect(ShortcutAction(key: action.key) == action)
        }
        #expect(ShortcutAction(key: "input:") == nil)
        #expect(ShortcutAction(key: "somethingNew") == nil)
    }

    @Test func aShortcutDoesOneThing() {
        let shortcut = Shortcut(keyCode: UInt32(kVK_ANSI_M), modifiers: cmdOption)
        var shortcuts = ShortcutSettings.assigning(shortcut, to: .toggleMute, in: [:])
        shortcuts = ShortcutSettings.assigning(shortcut, to: .selectInput(uid: "webcam"), in: shortcuts)
        #expect(shortcuts == [.selectInput(uid: "webcam"): shortcut])
        shortcuts = ShortcutSettings.assigning(nil, to: .selectInput(uid: "webcam"), in: shortcuts)
        #expect(shortcuts.isEmpty)
    }

    @Test func savedInConfig() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("tally-mic-tests-\(UUID().uuidString)")
        let url = folder.appendingPathComponent("config.json")
        let mute = Shortcut(keyCode: UInt32(kVK_ANSI_M), modifiers: cmdOption)
        let headset = Shortcut(keyCode: UInt32(kVK_ANSI_1), modifiers: UInt32(controlKey | optionKey))
        let store = ConfigStore(url: url)
        #expect(store.shortcuts.isEmpty)
        store.setShortcuts([.toggleMute: mute, .selectInput(uid: "a:b:c"): headset])
        try store.save()
        #expect(ConfigStore(url: url).shortcuts == [.toggleMute: mute, .selectInput(uid: "a:b:c"): headset])
    }
}
