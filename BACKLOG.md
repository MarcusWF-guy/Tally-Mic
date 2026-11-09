# Backlog

Deferred on purpose. Each item says what it is, why it's not in v1, and anything known so far. Add to this whenever something gets pushed out of a PR.

## Input

- **Live level meter** (the moving bars in System Settings). Needs microphone permission, and macOS shows the orange mic dot whenever it's running. If added: only while the panel is open, and add `NSMicrophoneUsageDescription` at the same time.
- **Push to talk.** Hold a shortcut to unmute while it's held. Carbon hot keys report key-up too (`kEventHotKeyReleased`), so it would fit the shortcuts built after Milestone 3 (SPEC 7.6).
- **Bluetooth headset hint.** Using AirPods (or most Bluetooth headsets) as the mic drops their audio playback quality while the mic is in use. A small secondary line on those rows could say so.
- **Know whether a wireless headset is actually on.** A wireless headset's USB receiver stays plugged in with the headset off, and Core Audio can't tell: compared with the headset off and on, every property of its mic is identical (Milestone 3b). The receiver does send private HID reports when the headset connects, but reading them would need Input Monitoring permission (it also presents itself as a keyboard) and working out each maker's undocumented protocol, which a firmware update could change. Instead, a headset's mic is only picked automatically while its headphones are the sound output (SPEC 6.2), which fits how Marcus uses it.
- **Per-app mic.** Zoom and Teams have their own mic settings, and there's no clean public way to change them from outside. Skip unless a real need shows up.

## Output

- **The Sound menu's slider for a monitor.** macOS greys out the slider in Control Center's Sound menu for sound sent to a monitor, and only a system audio driver could give it a volume to control. BetterDisplay doesn't do this either: its guide says Control Center doesn't become a DDC volume control. The volume keys do it instead (SPEC 7.7).
- **Monitor brightness keys.** The same DDC channel takes brightness (VCP 0x10), so the brightness keys could drive the monitor too, with macOS's brightness bubble drawn the same way.
- **Preferred order for outputs too.** Same rules and same setups, for speakers and headphones (Desk: headset, then monitor speakers; Laptop: headset, then MacBook speakers). The built-in Sound menu already handles picking an output, so only the auto part would be new.

## Setups

- **More triggers:** a USB dock or specific USB device connected, Wi-Fi network, power adapter connected, time of day.
- **Manual setup switch** in the panel, for times the trigger guesses wrong.

## Shared with Tally Cam

- **Bring Tally Mic's findings to Tally Cam** (being done in its own repo). Most apply there too: the SDK stamp fix in `Package.swift` (the grey Settings window), the right-click menu as the status item's own menu, macOS 27's expanded interface for the icon highlight, the Sound panel's measurements (360 pt, 16 pt corners, the drawn slider), and capturing its own windows to check the real UI (SPEC 11).
- **One shared UI package.** Pull the panel shell, rows, sliders and styling into a `TallyUI` Swift package both apps use, instead of copying. Worth it once both apps are stable.
- **One app, two menu bar icons.** Combine Tally Cam and Tally Mic into a single install. Only if keeping two apps up to date gets annoying.
- **Setups in Tally Cam.** For example, the webcam at the desk, the MacBook camera otherwise. Could share setup definitions with Tally Mic so both switch together.
- **Mic follows the call.** When Tally Cam detects a Zoom, Teams or Meet call, Tally Mic switches to a chosen "call mic." Needs the two apps to talk to each other (a shared notification).

## Sharing (from Milestone 4)

- **Apple-signed releases.** A Developer ID certificate (Apple Developer Program, $99 a year) plus notarization would let teammates open Tally Mic with a double-click, without the Open Anyway step. `release.sh` would sign with it and run `notarytool`.
- **An app icon.** Tally Mic has none, so Finder and macOS's first-open warning show a generic one. Ideally made with Tally Cam's, so the two match.
- **macOS 26 and Intel Macs.** Only macOS 27 on Apple silicon is supported, because that's all it's been tested on. macOS 26 would need the pre-27 icon highlight back; Intel would need a universal build, and monitor volume wouldn't work there (Intel Macs reach monitors a different way).
- **Accessibility pass** (planned for Milestone 4): VoiceOver labels throughout, and moving through the panel with the arrow keys and Return, like the Sound menu.
- **Reduce Transparency and Increase Contrast** (planned for Milestone 4): check the glass panel and bubbles with each turned on, and follow what Control Center does.
- **Switches drawn by Tally Mic,** if anyone in dark mode sees the panel's switches grey while on. Unlikely: the panel became the key window every time Marcus opened it, and then they're blue (SPEC 12, Milestone 4).
