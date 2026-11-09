import AppKit
import ApplicationServices

/// Catches the keyboard's volume keys (SPEC 7.7) before macOS acts on them. An event tap that can
/// swallow keys needs Accessibility permission; without it, `start()` fails and nothing changes.
@MainActor
final class VolumeKeyTap {
    struct Press {
        var key: MonitorVolume.Key
        var isDown: Bool
        var isRepeat: Bool
        var modifiers: NSEvent.ModifierFlags
    }

    /// Return true to take the key, so macOS never sees it; false to leave it to macOS.
    var onPress: ((Press) -> Bool)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isRunning: Bool { tap != nil }

    static var isAllowed: Bool { AXIsProcessTrusted() }

    /// Shows macOS's "Tally Mic would like to control this computer" prompt, which leads to
    /// System Settings > Privacy & Security > Accessibility.
    static func askForPermission() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(1) << Self.systemDefined,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let tap = Unmanaged<VolumeKeyTap>.fromOpaque(context).takeUnretainedValue()
                // The tap's run loop source is on the main run loop, so this is the main thread.
                nonisolated(unsafe) let mainThreadEvent = event
                let takes = MainActor.assumeIsolated { tap.takes(type, mainThreadEvent) }
                return takes ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: context)
        else {
            Log.error("Monitor volume: couldn't catch the volume keys (is Accessibility allowed?)")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.tap = tap
        self.source = source
        Log.info("Monitor volume: catching the volume keys")
        return true
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        source = nil
        Log.info("Monitor volume: stopped catching the volume keys")
    }

    // NX_SYSDEFINED events, subtype 8, carry the media keys: the key in data1's top 16 bits,
    // down (0xA) or up (0xB) in the next 8, and the repeat flag in the lowest bit.
    private static let systemDefined = 14
    private static let auxControlButtons: Int16 = 8
    private static let keys: [Int: MonitorVolume.Key] = [0: .up, 1: .down, 7: .mute]  // NX_KEYTYPE_SOUND_UP, _DOWN, _MUTE

    /// Whether Tally Mic takes this event, so macOS never sees it.
    private func takes(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Log.info("Monitor volume: macOS paused the key catcher; turning it back on")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard type.rawValue == UInt32(Self.systemDefined), let ns = NSEvent(cgEvent: event),
              ns.subtype.rawValue == Self.auxControlButtons, let key = Self.keys[(ns.data1 & 0xFFFF_0000) >> 16] else {
            return false
        }
        let flags = ns.data1 & 0xFFFF
        let press = Press(key: key, isDown: (flags & 0xFF00) >> 8 == 0xA, isRepeat: flags & 0x1 == 1,
                          modifiers: ns.modifierFlags.intersection(.deviceIndependentFlagsMask))
        return onPress?(press) == true
    }
}
