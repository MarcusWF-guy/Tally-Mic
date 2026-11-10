# Tally Mic: Spec

Last updated 2026-11-09. Status: Milestones 1 to 4 done, plus universal mute, keyboard shortcuts and monitor volume (7.5 to 7.7). Version 1.0 released. A public README, issue forms and a one-click download are in review, ahead of making the repo public.

This is the source of truth for how the app is built. Any change to behavior updates this file in the same PR.

---

## 1. What it is

A tiny native macOS menu bar app that does for **audio input** exactly what the built-in Sound menu does for output:

- Pick which microphone the Mac uses.
- Adjust input volume.
- Jump to Sound Settings.

Plus three small extras the built-in menu doesn't have:

- **Hide** inputs you never use (for example virtual devices that Zoom and Teams install).
- **Preferred order:** automatically use the best connected mic, so macOS stops switching to whatever was plugged in last.
- **Setups:** a separate preferred order for each way the Mac gets used. For example, **Desk** (plugged into the monitor): headset, then USB mic, then MacBook mic. **Laptop** (not plugged in): headset, then MacBook mic. The app switches setups automatically based on which display is connected.

And one that isn't about microphones, added after Milestone 3 because Tally Mic was the right place for it: **monitor volume** (7.7). While the sound plays through an external monitor, the keyboard's volume keys change the monitor's volume, the same as they do for the MacBook's speakers.

Sibling app to **Tally Cam** (formerly Fettle Cam, originally Keyframe), the webcam controller. Same look, same panel code, same way of working. Built for Marcus and his team, and public on GitHub so anyone can install it (README). Nothing is hosted: it runs entirely on the Mac.

## 2. Principles

1. **Indistinguishable from Apple's Sound menu.** Same layout, spacing, materials, fonts, icon circles and hover states. If someone opened the two menus side by side, the only difference should be the word "Input."
2. **One click.** Open, pick a mic, done.
3. **Light.** Native Swift, no Electron, no web views, no third-party UI kits. Near-zero CPU when idle (event-driven, no polling).
4. **No permission prompts unless a feature you turn on needs one.** Switching devices and setting input volume don't need microphone access. Don't add `NSMicrophoneUsageDescription` until a feature actually records audio (see BACKLOG: level meter). The one exception so far: monitor volume (7.7) needs Accessibility to catch the volume keys, and asks only when it's turned on. Marcus agreed to that.
5. **Easy for an AI to debug.** Plain JSON config, readable log file, a Copy Diagnostics button.

## 3. Environment and stack

| Item | Choice |
|---|---|
| Hardware | Developed and tested on a MacBook Pro with Apple silicon, both at a desk with an external monitor (lid open or closed) and on its own, with a range of inputs: a wireless headset's USB receiver, a USB webcam, a USB mic, the MacBook's own mic, a virtual device a meeting app installs, an iPhone's Continuity mic (over the air; it can take a few minutes to appear) and AirPods. |
| macOS | 27.2 (26B123) in Milestone 1. Match the current Sound menu look (Liquid Glass). **Requires macOS 27 on Apple silicon** (Milestone 4): it's the only version it has been tested on, so `LSMinimumSystemVersion` and the package's deployment target are 27.0, and the code paths for older versions (pre-glass backgrounds, the pre-27 icon highlight) were removed. On an older macOS the Mac refuses to open it. Built for arm64 only; monitor volume (7.7) needs Apple silicon anyway. |
| Language | Swift 6. SwiftUI for views, AppKit for the status item and panel. |
| Audio | Core Audio (`AudioObject` property APIs). No AVAudioEngine, no capture in v1. |
| Build | Swift Package Manager + Apple Command Line Tools (Swift 6.4). No Xcode project. Scripts wrap the binary into a `.app`. No SwiftUI `@State` (see 11). |
| Distribution | Not sandboxed, not notarized, not on the App Store. Signed with a local self-signed certificate (see 9). Marcus installs from source; teammates download a zip from the repo's GitHub releases (see 11). |
| License | MIT, unless code is copied from Tally Cam's GPL-3.0 camera layer (it shouldn't be; only the UI code is shared, and that's ours). |

## 4. Repo layout

```
tally-mic/
  README.md  DEVELOPMENT.md  CLAUDE.md  SPEC.md  BACKLOG.md  LICENSE
  .github/   ISSUE_TEMPLATE/ (bug and idea forms), readme/ (README images and download button)
  Package.swift
  Resources/Info.plist
  Sources/TallyMic/
    App/        entry point, AppDelegate, AppModel, StatusItemController, PanelController,
                SettingsWindowController, AutoSwitchController, HotKeyCenter, HUDController,
                MonitorVolumeController, VolumeKeyTap, VolumeHUDController (and MenuBarExtras),
                LoginItem, SoundSettings, DeviceSettings, SetupSettings, ShortcutSettings
    UI/         PanelView, PanelChrome (metrics, glass, shadow, hover), DeviceRow, DeviceIcon,
                VolumeSlider, SetupSection, ShortcutRecorder, VolumeHUDView, GeneralSettingsView,
                DevicesSettingsView, SetupsSettingsView, ShortcutsSettingsView
    Audio/      AudioHAL (typed Core Audio calls, listeners), AudioSystem, InputDevice, VolumeControl,
                MuteControl, MicUsage
    Displays/   Lid, DisplayMonitor, MonitorDDC (a monitor's DDC/CI channel)
    Logic/      ConfigStore, DeviceList, Setup and SetupResolver, AutoSwitcher, Shortcut,
                MonitorVolume (steps, DDC bytes, which display a sound output is) (pure logic)
    Support/    Log, Diagnostics
  Tests/TallyMicTests/   icons, config, diagnostics, device list, setups, auto switching, shortcuts,
                         monitor volume, panel layout and placement
  scripts/  build.sh  install.sh  make-cert.sh  release.sh
```

## 5. UI

### 5.1 Menu bar icon

- SF Symbol `mic` as a template image, so it adapts to light and dark menu bars. `mic.slash` while muted (7.5), and `.fill` on either while any app is recording from a microphone, the way Tally Cam fills its camera icon while the camera is in use. "Recording" comes from Core Audio's per-app process objects (`kAudioProcessPropertyIsRunningInput`, macOS 14 and later), not from whether a device is running: some headsets are one device for both speaker and mic, so playing music would count. Reading it needs no microphone permission, and Tally Mic never records, so it never counts itself.
- Left click toggles the panel. Right click: Settings…, Quit Tally Mic.
- **The icon stays highlighted while the panel is open**, like the Sound icon. On macOS 27 the panel is the status item's "expanded interface" (`NSStatusItem.expandedInterfaceDelegate`): the menu bar starts a session on a left click and draws the highlight until the session ends. Tally Mic opens the panel when a session begins, closes it when one ends, and cancels the session whenever the panel closes by itself. Tested with Marcus using a throwaway icon: left clicks go to the session and no longer arrive as the button's action; right clicks still do; Esc ends the session; clicks elsewhere don't, so the app has to; and a second click on the icon reaches the app only as a click in another app (the menu bar handles it), which the panel's outside-click watcher already treats as "close". The menu bar also runs the right-click menu as a session, which arrives like a panel session, so at first the panel opened alongside the menu (found by Marcus). A session that begins while the menu is open, within half a second of a right click, or while the right button is down opens no panel. It isn't cancelled either: that closes the menu straight away. Any session still running when the menu closes is ended, with its panel if one opened.
- The right-click menu is the status item's own menu (set `statusItem.menu` and click the button), so macOS places and styles it like every other menu bar menu. Popping it up from the button with `NSMenu.popUp(positioning:at:in:)` gave it the menu bar's dark, translucent look and put it in the wrong place. No keyboard shortcuts and no icons, like the menus of Apple's own menu bar icons. Right-clicking closes the panel if it's open.

### 5.2 Panel behavior (same as Tally Cam)

- Borderless, non-activating `NSPanel` hosting SwiftUI, dropping down from the icon.
- Stays open and in place when switching desktops (`collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`, `hidesOnDeactivate = false`).
- Closes on clicking the icon again, clicking anywhere outside, or Esc.
- Never steals focus from the app you're in.
- Width and corner shape match the Sound menu: **360 pt wide, 16 pt corners**, measured pixel by pixel from a Retina screenshot of the Sound panel on macOS 27.2 after Milestone 1. Tally Mic first copied Tally Cam's 320 pt and 12 pt, which were too small: the Sound panel showed a long headset name in full where Tally Mic cut it off.
- **How it was matched:** `TALLY_SNAPSHOT_DIR` renders the panel offscreen, and the same pixel measurements run on both images. Every element now sits within 1 px (0.5 pt) of the Sound panel's. Offscreen renders match the real panel because nothing in it is a system control whose look depends on the window: the slider is drawn by Tally Mic (see 5.3). Checked against a second screenshot with the Sound slider active, and against captures of the real panel on screen (see 11).
- **Copy the panel shell and row components from Tally Cam** so both apps look identical. Apply the known Tally Cam fixes while copying: switches right-aligned to the trailing edge. Copied in Milestone 1: the panel window and its placement math, the glass background and drawn shadow, `PanelMetrics` (then 320 pt wide with 12 pt corners, since measured as 360 and 16; 14 pt insets), the section header, footer and row styles. The panel has no switches yet.
- Rows highlight under the pointer like native menu rows: a light rounded rectangle (8 pt corners), inset 5 pt from the panel's edges. Tally Cam's rows don't have this yet.

### 5.3 Panel layout

Mirror the Sound menu top to bottom:

1. **Title:** "Microphone", 13 pt semibold, the same as "Sound". (13 pt bold measured 2 px wider.) A switch at the trailing edge turns the microphone on or mutes it (7.5), like the switch beside "Wi-Fi" in its panel; it's laid over the row so the measured spacing stays. Disabled, with a tooltip, when the current input can't be muted. The volume slider dims while muted.
2. **Input volume slider.** Same style as the Sound menu's slider, no label, no number. Controls the current input's volume. The icons are the mic with a level meter that System Settings uses for input volume (`mic.and.signal.meter.fill`, 13 pt), with the meter empty on the left and full on the right, in place of the Sound panel's quiet and loud speakers. The track sits exactly where the Sound panel's does (34.5 to 315 pt from the left edge); the Sound panel's loud speaker is wider than its quiet one, so the track is left of center and there's room to the right of the loud mic. The track and knob are drawn by Tally Mic to the Sound panel's measurements: a 6 pt track (`.quaternary` grey, accent blue up to the knob) and a white pill knob 20 pt wide and 16 pt tall with a soft shadow, which stays on the track. SwiftUI's `Slider` couldn't match it: in a panel on macOS 27 it draws a 4 pt track and a round knob whatever control size is set, and lays out about 4 pt taller on screen than in offscreen renders, which pushed everything below it down. Pressing anywhere on the track jumps there and dragging follows; VoiceOver can adjust it in 5% steps. Greyed out with no knob when the device has no software volume (see 7.3): a grey 6 pt track takes the slider's place at the same height, and the icons turn lighter, so the panel doesn't change size.
3. Divider.
4. **Section header "Input"**, 12 pt bold in a lighter grey than secondary text, the same as "Output".
5. **One row per visible input device.** Circle icon on the left, device name. Rows are 32 pt apart (26 pt circle, 3 pt above and below), with 8 pt between the circle and the name, and the grey circle is a touch lighter than `.quaternary`. The active device has the blue filled circle with a white glyph; others get the grey circle. Hover highlight like native rows. Clicking a row makes that device the system input; the panel stays open so you see the circle move. Inputs hidden in the Devices tab are left out, except the current input, which always shows so the panel never hides what's in use. Rows use the names given in the Devices tab and are listed in the active setup's order (asked for by Marcus after Milestone 3b), the same order as in the Setups tab, so the list changes when the setup changes. Inputs Tally Mic hasn't recorded yet come last, by name. Names up to about 290 pt fit, such as a 41-character headset receiver's name; a longer one is shortened in the middle. With no inputs at all, the list says "No microphones found."
6. Divider, then two rows, always shown, laid out like Control Center's rows (label on the left, value or switch at the trailing edge, 13 pt): **Setup**, with the detected setup's name in secondary text on the right, shown whether or not switching is on; and **Automatic Switching**, with a switch, the same setting as General's checkbox. Marcus asked for exactly these two things after a first try with a round-icon row and status text, which was too busy. The "Auto" label on the current input and the "Switch Automatically" row under the inputs were dropped with it: picking a mic by hand turns the switch off instead (6.2), so the switch always says whether Tally Mic is choosing.
7. Divider, reaching closer to the edges than the one under the slider (6 pt from each edge instead of 14), like the Sound panel's.
8. **Footer row** with two buttons, each styled like the Sound menu's "Sound Settings…" with its own hover highlight. Both close the panel first.
   - **"Tally Mic Settings…"** on the left, aligned to the leading edge. Opens Tally Mic's Settings window, the same as right-click > Settings…. The Sound menu has no equivalent; Marcus asked for it after Milestone 1.
   - **"Sound Settings…"** on the right, aligned to the trailing edge. Opens System Settings > Sound on the Input tab, with `x-apple.systempreferences:com.apple.Sound-Settings.extension?input`. The Sound pane's extension lists `input`, `output`, `effects` and `soundEffects` as deep link anchors on macOS 27.2.

### 5.4 Row icons

Pick an SF Symbol from the device's transport type and name:

| Device | Symbol |
|---|---|
| Built-in (MacBook) | `laptopcomputer` |
| AirPods / AirPods Pro / AirPods Max (name match) | `airpods`, `airpodspro`, `airpodsmax` |
| Other Bluetooth | `headphones` |
| USB headset or receiver (name contains headset, HS, receiver) | `headphones` |
| Webcam mic (name contains Brio, Insta360, Link, cam) | `web.camera` |
| Other USB | `mic` |
| DisplayPort / HDMI / Thunderbolt display | `display` |
| iPhone (Continuity) | `iphone` |
| Virtual / aggregate | `waveform` |

Name matches are case-insensitive and live in one table (`DeviceIcon.nameRules`) so they're easy to extend. Checked in this order: the transport first for built-in, virtual or aggregate, display and Continuity devices; then the name table; then Bluetooth, then everything else gets `mic`. "HS" counts only at the start of a word (gaming headsets named like "HS70") and "Link" only as a whole word, so they don't match inside other names ("LinkBuds").

### 5.5 Settings window

Standard macOS Settings window, three tabs. Each tab uses the classic layout Apple's own apps use for their Settings windows (Safari, Mail, Notes), which Marcus picked over the System Settings look. The window is pure white like Mail's and Maccy's. It was light grey until the build was fixed to stamp the app with the real SDK version (see 11): stamped "macOS 14 SDK", macOS 27 gives an app the older look. The layout: labels on the left ending in a colon and right-aligned, controls on the right, checkboxes rather than switches, explanations in small grey text, and full-width dividers between groups. It's built as a SwiftUI `Grid`, because a `.columns` Form only draws dividers across the control column.

- **General:** Startup: Launch at login. Preferred order: a "Switch microphones automatically" checkbox with a short explanation (Milestone 3b), the same setting as the panel's switch. Off until Marcus turns it on, since it changes the mic by itself. Volume keys: a "Control external monitor volume" checkbox (7.7), off by default; while it's on and Accessibility isn't allowed yet, a note says so with an "Open Accessibility Settings…" button. Meeting apps: the reminder (see 8). Troubleshooting: Copy Diagnostics, Show Config File, Show Log (both show the file in Finder). Version: the version and build, with a "Releases on GitHub…" button (Milestone 4). If macOS wants the login item approved, a note says so with an "Open Login Items…" button.
- **Devices:** every input macOS has ever reported to Tally Mic, connected or not, in the order first seen, as a standard table with four columns:
  - **Show:** a checkbox. Unticked inputs don't appear in the panel, unless one is the current input.
  - **Microphone:** its icon and the name macOS reports, greyed out while it isn't connected.
  - **Name in Menu:** an optional shorter name for the panel ("Headset" for a long name like "Wireless Gaming Headset Receiver"). The field shows the real name in grey until a name is typed, and it's saved as it's typed. Clearing it goes back to the real name.
  - **Status:** "Connected", or "Not connected" with a **Forget** button that removes the input from the list. If it connects again it's added back as new, shown and unnamed. Connected inputs can't be forgotten, since they'd be added straight back.
  A line of grey text under the table explains this. The settings apply in every setup.
- **Shortcuts** (7.6): one row each for Mute or unmute, Automatic switching and Open the menu, then "Switch to:" with one row per known microphone, by its shown name (hidden ones greyed). Every shortcut box sits in one column. A clear (x) button appears beside a set shortcut, and "macOS already uses this shortcut. Pick another." in red under the box when it clashes with one of macOS's own. A note under the grid explains how to record. Added after Milestone 3.
- **Setups:** list of setups on the left, the selected setup's details on the right. Built in Milestone 3a:
  - **The list** is checked top to bottom; the active setup says "Active". Drag to reorder; the fallback setup always stays last. **+** adds a setup for a display no setup uses (a connected one first, else one seen before), named after the display and checked before the fallback; it's disabled until there's such a display. **−** deletes the selected setup; the fallback can't be deleted.
  - **Name:** editable, saved as typed (a blank name shows as "Untitled").
  - **Active when:** a picker of displays seen before, "is connected", and a **Use Current Display** button below it. For the fallback: "No other setup's display is connected", not editable.
  - A green dot and "Active now" when the setup is active, else "Not active".
  - **Order:** every known microphone, numbered, as a list to drag. Inputs the setup doesn't list come last in the order first seen (6.1). Hidden ones are greyed with "Hidden", disconnected ones say "Not connected".
  - When an external display is connected that no setup uses, a bar at the top says so with an **Add a Setup for [display]** button.
  - Until Milestone 3b, a line under the order says automatic switching isn't turned on yet.

## 6. Preferred order and setups

The problem: when a device connects (AirPods, a webcam, the monitor), macOS often makes it the input. That's usually wrong. And the right mic depends on where the Mac is: docked at the desk or out on its own. Same computer, two setups.

### 6.1 Setups

- A **setup** is a name, a trigger, and a preferred order of input devices.
- **Trigger:** "this display is connected." Match by vendor ID, model ID and serial number (`CGDisplayVendorNumber`, `CGDisplayModelNumber`, `CGDisplaySerialNumber`), falling back to the display's name (`NSScreen.localizedName`) when the numbers are zero or missing. Two monitors of the same model are told apart by serial number. The Mac's own screen never counts. Every external display Tally Mic sees is remembered in config.json (`displays`) for the Setups tab's picker.
- Setups are checked top to bottom; the first whose trigger matches is active. The last setup has no trigger ("Otherwise") and is the fallback. There's always at least one setup.
- **First run:** one setup, "Laptop", with no trigger. When an external display is connected that no setup uses, the Setups tab offers "Add a setup for [display name]." Marcus's intended pair: **Desk** (the external monitor connected) and **Laptop** (otherwise).
- Devices missing from a setup's order go to the bottom, in the order Tally Mic first saw them. Show/hide and display names are shared across setups.

### 6.2 Picking the mic

- Use the first device in the active setup's order that is connected, visible and available.
- Hidden devices are never picked automatically.
- The MacBook mic counts as unavailable while the lid is closed. Apple silicon MacBooks disconnect the mic in hardware when the lid shuts, but it still shows in the device list. Read the lid state from IOKit (`AppleClamshellState`). **Confirmed in Milestone 1** (lid closed with an external monitor, macOS 27.2): "MacBook Pro Microphone" stays in the list, reports itself alive (`kAudioDevicePropertyDeviceIsAlive` = 1) and keeps a settable volume, so nothing in Core Audio tells you it's off. `AppleClamshellState` reads Yes. Copy Diagnostics shows the lid state.
- **A headset's mic only while it's the sound output.** A wireless headset's USB receiver stays plugged in with the headset off, and macOS can't tell: with the headset off and on, every Core Audio property of its mic is identical, and only the headphone side changes when sound starts playing (compared in Milestone 3b). Reading the receiver's own messages would need Input Monitoring permission, since it also presents itself as a keyboard. So a headset's mic (an input whose icon is headphones or AirPods, 5.4) is only picked automatically while one of its own outputs is the sound output. Its outputs are the devices `kAudioDevicePropertyRelatedDevices` links it to that have output streams, plus itself if it has any: a USB headset receiver's mic and headphones are two devices linked that way. Marcus: when he uses a headset's mic, he's listening through it too. Mics that aren't headsets (the MacBook mic, USB mics, webcams) ignore the sound output.
- **Picking a mic by hand turns automatic switching off** (Marcus's choice in Milestone 3b, replacing pins), and it stays off until it's turned back on. That covers a click in the panel and a change made in System Settings.
- **Who changed the input?** Every default input change fires the same notification, so sort it by source:
  - **Tally Mic's own auto-switch:** remember the device just set, and ignore the matching notification that arrives within 1 second. Without this, the app's own switch would look like a manual pick and turn switching off.
  - **A click in the panel:** always a manual pick. The click turns switching off before switching, so it counts even right after a device connects.
  - **Anything else** (macOS or System Settings): if it happens within 2 seconds of a device or display connecting or disconnecting, treat it as macOS and re-apply the preferred device. Otherwise treat it as a manual pick and turn switching off.
- **Settle first.** Docking fires a burst of display and audio events. Wait until things have been quiet for 1.5 seconds, then decide once, so the mic doesn't flip back and forth.
- **Built in Milestone 3b** (`AutoSwitcher`, pure, with the times passed in; `AutoSwitchController` feeds it):
  - When a device connects, macOS can announce the new input before the new device. So an input change is sorted by who made it 0.4 seconds after it arrives, still measured from when it happened, and a switch to an input Tally Mic hasn't listed yet counts as a device change too.
  - Turning switching on decides at once. The setting is saved, so it stays on or off across restarts.
  - The lid is watched through the power manager's general-interest notifications (IOKit), reading `AppleClamshellState` again on each. Wake comes from `NSWorkspace.didWakeNotification`. Both count as device changes.
  - Every decision is logged with its reason ("Auto: Desk prefers Wireless Headset; switching from Webcam Mic", "Auto: macOS switched to AirPods as something connected or disconnected; deciding again once things settle", "Automatic switching turned off: Webcam Mic picked in the panel").
- Re-evaluate when: a device connects or disconnects, a display connects or disconnects, the lid opens or closes, the Mac wakes from sleep, the sound output changes, switching is turned on, or setups or devices are edited.

**SetupResolver** (displays + setups in, active setup out) and **AutoSwitcher** (devices + active setup + events in, desired device out) are pure logic with unit tests covering: docking, undocking, no matching display, display matched by name only, connect, disconnect, lid close while docked, hidden device, a headset only while it's the sound output, other mics ignoring the sound output, macOS auto-switch vs manual change, a device change announced just after the input change, Tally Mic's own switch not counting as manual, event bursts.

## 7. Audio layer (Core Audio)

### 7.1 Devices

- List devices with `kAudioHardwarePropertyDevices`. A device is an input if `kAudioDevicePropertyStreams` in the input scope is non-empty.
- Per device: name (`kAudioObjectPropertyName`), UID (`kAudioDevicePropertyDeviceUID`), transport type (`kAudioDevicePropertyTransportType`).
- **Identity:** key config by UID. Some USB devices without a serial number get a UID that includes the USB port, so the UID changes if you move ports. Fallback: if a saved UID is missing but a connected device has the same name and transport type, treat it as the same device and update the stored UID.

### 7.2 Switching

- Read and set the system input with `kAudioHardwarePropertyDefaultInputDevice`.
- Read the result back after setting it, and log it if it didn't stick.

### 7.3 Input volume

- `kAudioDevicePropertyVolumeScalar`, input scope. Try the main element (0) first. If it isn't settable, set each channel element (1, 2, …) to the same value and show the average.
- Check settability with `AudioObjectIsPropertySettable`. If nothing is settable, the slider shows disabled, same as System Settings.
- Debounce writes (about 30 ms) while dragging: at most one write every 30 ms, always with the latest value.
- Devices answer each write with a volume notification, sometimes rounded to their own steps. For 300 ms after a change from the slider, those are ignored, so the knob doesn't jitter under the pointer.
- **Found in Milestone 1:** a wireless headset's USB receiver had no main-element volume and is set through channel 1, so it uses the per-channel path. A two-channel webcam, a USB mic, the MacBook Pro Microphone and Microsoft Teams Audio are set through the main element. An iPhone's Continuity mic has no settable volume, so it gets the greyed slider.
- **Don't trust the Continuity transport type.** The iPhone mic reports `'ccwd'` (`kAudioDeviceTransportTypeContinuityCaptureWired`, "connected via a cable" in Apple's header) even though the iPhone wasn't plugged in; no iPhone was on USB. Both Continuity types get the same icon, so nothing depends on it, and nothing should.

### 7.4 Staying in sync

Property listeners, no polling:

- Device list changes (`kAudioHardwarePropertyDevices`).
- Default input changes (`kAudioHardwarePropertyDefaultInputDevice`), including changes made in System Settings.
- Volume changes on the current input (so the slider moves if something else changes it).
- Name changes.
- The sound output (`kAudioHardwarePropertyDefaultOutputDevice`), since a headset's mic follows its headphones (6.2).
- Which apps are recording, for the menu bar icon. **macOS 27.2 never announces changes to `kAudioProcessPropertyIsRunningInput`**: it can be read, but no listener fires (found with a Voice Memos test after Milestone 1; the first version of the icon missed recordings). What is announced: the app list (`kAudioHardwarePropertyProcessObjectList`), each app starting or stopping audio of any kind (`kAudioProcessPropertyIsRunning`), and each input device starting or stopping (`kAudioDevicePropertyDeviceIsRunningSomewhere`). Tally Mic listens for all three and reads `IsRunningInput` for every app each time. The per-app listeners are rebuilt when apps start or quit.
- Display changes (`NSApplication.didChangeScreenParametersNotification`), for setups.
- Plus `NSWorkspace.didWakeNotification` and lid state changes.

The panel updates live while open. Displays arrived in Milestone 3a; wake and the lid in 3b.

### 7.5 Universal mute

Asked for by Marcus after Milestone 3 (it was in BACKLOG).

- One mute that follows you across microphones: Tally Mic's mute state is the truth, and whichever input is current always matches it. When the input changes while muted (automatically or by hand), the new input is muted too; while unmuted, an input left muted earlier is unmuted when it becomes current.
- How an input is muted (`MuteControl`): its own mute switch (`kAudioDevicePropertyMute`, input scope, main element, settable), else its volume set to zero and the old volume put back on unmute, else not at all. In testing, every input but an iPhone's had a settable mute; the iPhone has neither, so it can't be muted, and the panel's switch is disabled while it's the input. The menu bar icon and panel only ever show a mute that's really happening (`effectivelyMuted`).
- At launch the state is read from the current input rather than applied to it, so starting Tally Mic never unmutes anything. A mute or unmute made elsewhere (another app, the device itself) is picked up from the current input's mute listener.
- Shown by the menu bar icon (`mic.slash`), the switch in the panel's title row, and the dimmed volume slider. Copy Diagnostics says whether the current input is muted.

### 7.6 Keyboard shortcuts

Asked for by Marcus after Milestone 3: optional, for the controls where they make sense.

- All optional and unset until set in Settings > Shortcuts: **Mute or unmute**, **Automatic switching** on/off, **Open the menu**, and **Switch to** each known microphone. Switching to a microphone by shortcut counts as picking it by hand, so it turns automatic switching off (6.2), and says "picked with a shortcut" in the log.
- Global, through Carbon's `RegisterEventHotKey` (`HotKeyCenter`): they work in any app, ahead of that app's own shortcuts, and need no Accessibility or Input Monitoring permission.
- Clashes: macOS registers a shortcut even when it already uses those keys itself (tested: ⌘Space and ⌘⇧3 were accepted, even with `kEventHotKeyExclusive`). So Tally Mic first checks macOS's own shortcuts that are turned on (`CopySymbolicHotKeys`, the list in System Settings > Keyboard > Keyboard Shortcuts), doesn't register a clashing one, and the tab says so in red. Another app's shortcuts can't be seen (a second process registering the same keys also succeeded), so a clash with one isn't flagged.
- Recording (`ShortcutRecorder`, an NSButton): click, then type. Keys need ⌘, ⌥ or ⌃, except function keys, so typing never triggers a shortcut. Esc cancels, Delete clears. While recording, no shortcut fires, so typing one that's already set records it instead of running it. A shortcut does one thing: giving it to an action takes it from any other. Shown the way macOS menus write them, ⌃⌥⇧⌘ then the key, with the key's name from the current keyboard layout.
- Feedback: a small glass bubble under the menu bar icon (`HUDController`) for about 1.4 seconds: "Microphone Muted", "Microphone On", "Automatic Switching On", the microphone's name, or "… Can't Be Muted" / "… Isn't Connected". It never takes clicks or focus.
- Saved in config.json as `shortcuts`: `{"toggleMute": {"keyCode": 46, "modifiers": 2304}, "input:<UID>": {…}}`, with Carbon key codes and modifier flags.

### 7.7 Monitor volume

Asked for by Marcus after Milestone 3: BetterDisplay used to do this, and it's gone. At a desk the sound often plays through the external monitor's speakers over its cable, and macOS can't set the volume of sound sent that way, so the volume keys show a "not allowed" sign and the Sound menu's slider is greyed out.

- **Off until turned on** in Settings > General ("Control external monitor volume"), saved as `general.controlMonitorVolume`. Turning it on asks for Accessibility permission (macOS's own prompt, which leads to Privacy & Security > Accessibility). Until it's allowed, nothing changes and General says so. Tally Mic notices when it's allowed (macOS announces changes to that list) and also checks whenever Settings opens.
- **When it acts:** only while the sound output is a display's audio (Core Audio transport DisplayPort or HDMI, or a UID made from a display's IDs) that has no volume macOS can set. With the sound on the MacBook's speakers, a headset or AirPods, the keys are left alone and work as normal. So does a monitor whose volume macOS can already set.
- **Which monitor:** a display's audio output UID starts with bytes from the display's EDID: the vendor ID, then the product ID low byte first. For example `ABCD3412-…` is vendor 0xABCD and product 0x1234, the same IDs as its display. Tally Mic matches that against each external display's IDs. If that fails and there's only one external display, it uses that one.
- **The keys** (`VolumeKeyTap`): an event tap for the media key events (NX_SYSDEFINED, subtype 8: sound up, down, mute) that swallows the ones it handles, so macOS doesn't also show its "not allowed" bubble. It needs Accessibility, as it does for MonitorControl and BetterDisplay. Like macOS but finer: 64 steps rather than macOS's 16 (Marcus found 16, then 32, too coarse for his monitor), snapping to the nearest, or one per level on a monitor with fewer than 64; ⇧⌥ for the monitor's own smallest step (often 1 of 100), where macOS gives quarter steps; the mute key toggles, and volume up or down unmutes; ⌥ with a volume key is left to macOS, which opens Sound settings. If "Play feedback when volume is changed" is on in Sound settings, the feedback sound plays (through the monitor) when the key comes up; ⇧ flips that, as in macOS.
- **The monitor** (`MonitorDDC`): DDC/CI over the video cable, VCP code 0x62 (speaker volume), through `IOAVService`. That isn't public API, but MonitorControl, BetterDisplay, Lunar and m1ddc all use it and it hasn't changed since 2020; it's looked up at run time, so if macOS removes it the feature finds no monitors and the keys are left to macOS. Each display's framebuffer (`IOMobileFramebufferShim` on this Mac) is followed in the I/O registry by its `DCPAVServiceProxy` with Location "External"; Tally Mic pairs them in that order, as MonitorControl does. The current volume is read when the sound moves to the monitor (each read can take 100 ms or more, and some get no reply, so up to six tries). Writes are sent twice, 10 ms apart, as MonitorControl does, on a background queue; only the newest value is sent, so holding a key down doesn't build a backlog. Mute sets the monitor's volume to 0 and remembers the level. If a write fails, the monitor is looked up again (its connection is rebuilt after sleep, for example). Tested with a monitor whose volume BetterDisplay could also control.
- **The bubble** (`VolumeHUDView`, `VolumeHUDController`): macOS no longer lets other apps show its own volume bubble (MonitorControl's notes say the level in it doesn't update since macOS 26, and BetterDisplay draws its own on 27.2), so Tally Mic draws a copy, measured from a 2x screenshot of the real one at half volume over a white window: 308 × 64 pt capsule of clear Liquid Glass darkened 18% (211 over white, like the real one; regular glass measured 245), a 1 px rim darker at the ends and lighter along the top and bottom, a white speaker symbol 26.3 pt (glyph 28.5 × 22.5 pt) 20.5 pt from the left (`speaker.slash.fill` muted or at 0, then `.wave.1`, `.wave.2`, `.wave.3` by thirds), and a bar 62.5 pt from the left, 214 × 4 pt, of 16 segments 1 pt apart with rounded outer ends, lit white and unlit white at 50%; with 64 steps, each step lights a quarter of a segment. Checked against the real one on a 1x external monitor: size, height and the icon's and bar's positions match within 1 pt. It sits 11 pt below the menu bar, centered under the Sound icon (identifier `com.apple.menuextra.sound`), else at the top right. The icon is found through Accessibility. On macOS 27 the menu bar icons belong to MenuBarAgent, not Control Center, and asking it for its list of icons (`AXExtrasMenuBar`) came back empty 43 times out of 44 in testing; asking what's at a point on screen works every time, so Tally Mic checks points along the menu bar from the right, 8 pt apart, until it hits the Sound icon (a 22 × 22 pt item). It looks when the monitor is found, so a key press only needs one check that the icon is still there. The first build looked in Control Center, found nothing, and showed the bubble at the top right (found by Marcus). It shows for 1.5 seconds after the last press, then fades over 0.3. Unlike the real one, it can't highlight the Sound icon while it shows.
- **Not done:** making the Sound menu's own slider (Control Center) move the monitor's volume. That would take a system audio driver; BetterDisplay doesn't do it either (see BACKLOG).
- Copy Diagnostics shows how the sound output is connected, whether macOS can set its volume, whether Accessibility is allowed, and where the Sound icon was found.

## 8. Meeting apps (user setup, not code)

Zoom, Teams and Meet can each pick their own mic and ignore the system input. For switching in Tally Mic to carry through, set each app's mic to its follow-the-system option once (Zoom calls it "Same as System"). README covers this. Settings > General shows a one-line reminder.

## 9. Permissions and signing

- **No privacy prompts unless a feature you turn on needs one.** So far only monitor volume (7.7), which needs Accessibility to catch the volume keys. The grant is tied to the app's signature, so the stable "Tally Local" certificate below keeps it across rebuilds.
- Launch at login via `SMAppService.mainApp`. **On by default:** the first time Tally Mic runs from `/Applications`, it turns launch at login on and records `general.launchAtLogin` in config.json, so it only does this once. macOS shows a "Login Item Added" notification. Turning it off in Settings sticks. Copies run from the build folder never register themselves.
- **Releases** are signed with the same "Tally Local" certificate as Marcus's own builds. macOS ties Accessibility and the login item to the signature (the bundle ID plus the certificate), so they carry over when a teammate installs an update. A different certificate would make them grant Accessibility again. Gatekeeper rejects the download on first open, as it does any app not notarized by Apple (checked with `spctl` on a quarantined copy: rejected, origin Tally Local), so teammates click Open Anyway in Privacy & Security once (README). An Apple Developer ID and notarization would remove that step (BACKLOG).
- **Signing:** `scripts/make-cert.sh` creates a self-signed certificate named "Tally Local" in the login keychain only if it doesn't exist (asks for the Mac password once). Tally Cam currently signs with "Keyframe Local" and can move to "Tally Local" when it's renamed, so both apps share one certificate. A stable signature keeps the login item registered across rebuilds.
- **Info.plist:** `LSUIElement = YES` (no Dock icon), bundle ID `dev.marcus.tally-mic`.

## 10. Config, logs, diagnostics

- **Config:** `~/Library/Application Support/Tally Mic/config.json`. Human-readable, `version` field, written atomically, unknown keys preserved.
- **Logs:** `~/Library/Logs/Tally Mic/tally-mic.log` (rolling, 2 MB) plus `os_log` subsystem `dev.marcus.tally-mic`.
- **Devices** are recorded in config.json from Milestone 1 on, in the order Tally Mic first sees them, with the UID fallback from 7.1. That way the Devices tab and preferred order have a history to start from.
- **Copy Diagnostics:** macOS version, every input device (name, UID, transport type, icon, channel count, volume settable or not and how, current volume), current default input, which apps are recording, lid state, config, last 50 log lines. The log notes when the mic starts and stops being used, and by which app.
- **From Terminal:** `"/Applications/Tally Mic.app/Contents/MacOS/TallyMic" --diagnostics` prints the same report and quits. It only reads; it changes nothing.

Example config (values illustrative):

```json
{
  "version": 1,
  "preferredOrderEnabled": true,
  "devices": [
    { "uid": "AppleUSBAudioEngine:Unknown Manufacturer:Headset:...", "name": "Wireless Gaming Headset Receiver", "transport": "usb", "displayName": "Headset", "visible": true },
    { "uid": "AppleUSBAudioEngine:...:USBMic", "name": "USB Microphone", "transport": "usb", "displayName": null, "visible": true },
    { "uid": "BuiltInMicrophoneDevice", "name": "MacBook Pro Microphone", "transport": "builtIn", "displayName": null, "visible": true },
    { "uid": "ZoomAudioDevice_UID", "name": "ZoomAudioDevice", "transport": "virtual", "displayName": null, "visible": false }
  ],
  "setups": [
    {
      "id": "desk", "name": "Desk",
      "trigger": { "type": "display", "name": "Desk Monitor", "vendorId": 1234, "modelId": 0, "serial": 0 },
      "order": ["AppleUSBAudioEngine:Unknown Manufacturer:Headset:...", "AppleUSBAudioEngine:...:USBMic", "BuiltInMicrophoneDevice"]
    },
    {
      "id": "laptop", "name": "Laptop",
      "trigger": null,
      "order": ["AppleUSBAudioEngine:Unknown Manufacturer:Headset:...", "BuiltInMicrophoneDevice"]
    }
  ],
  "displays": [
    { "type": "display", "name": "Desk Monitor", "vendorId": 1234, "modelId": 5678, "serial": 4321 }
  ],
  "general": { "launchAtLogin": true }
}
```

Setups are checked in array order. The one with `"trigger": null` must be last.

## 11. Build, install, test

- `scripts/build.sh`: `swift build -c release`, assemble `build/Tally Mic.app`, sign with "Tally Local". The build number (`CFBundleVersion`) is the commit count plus 55, the builds made before the repo went public with a fresh history, so it keeps going up (1.0 is build 50).
- `scripts/install.sh`: build, quit the running copy, replace `/Applications/Tally Mic.app`, relaunch.
- `scripts/release.sh` (Milestone 4): publishes a release teammates download. The version is `CFBundleShortVersionString` in `Resources/Info.plist`, bumped in a PR like any change (1.0 is the first); the build number comes from `build.sh`. Run on an up-to-date, clean `main`, it refuses a version that's already released, builds, zips with `ditto` (which keeps the signature; about 0.5 MB), unzips a copy to check the signature, and creates GitHub release `v<version>` with the zip and install notes. The zip is always named `Tally-Mic.zip`, so `releases/latest/download/Tally-Mic.zip`, the README's download button, always gets the newest release. Settings > General shows the version with a "Releases on GitHub…" button.
- `swift test`: device icons, config, diagnostics, panel layout and placement; AutoSwitcher from Milestone 3. `TALLY_SNAPSHOT_DIR=/some/folder swift test` also saves PNGs of the panel, for checking layout without opening the app (the glass doesn't draw offscreen).
- All building and testing happens in a **local** Claude Code session on the Mac. Cloud sessions run on Linux and can't build Mac apps or see audio devices.
- **The SDK stamp.** SwiftPM's new build system passes the SDK to the final link as `--sysroot`, which doesn't tell the linker the SDK's version, so it stamped the binary with the deployment target instead (`sdk 14.0`). macOS 27 then treats Tally Mic as an old app and gives it the pre-Liquid Glass look: a grey Settings window, older menus and controls. `Package.swift` passes `-isysroot` to the link so the real version is stamped. Check with `otool -l "/Applications/Tally Mic.app/Contents/MacOS/TallyMic" | grep -A4 LC_BUILD_VERSION`: `sdk` should match `xcrun --show-sdk-version`, not 14.0. Tally Cam is built the same way and likely has the same problem.
- **Seeing the real UI.** An app can capture its own windows on screen without Screen Recording permission, through `CGWindowListCreateImage` (looked up with `dlsym`, since the SDK marks it unavailable). A throwaway program that compiles Tally Mic's sources, opens the panel or Settings window and captures it shows exactly what Marcus sees, apart from the backdrop behind the glass. Offscreen renders (`TALLY_SNAPSHOT_DIR`) don't show window materials or SDK-dependent styles.
- **The public repo** (Milestone 4). `README.md` is the public page: a download button (`.github/readme/download.svg`, drawn in the repo rather than a badge service), a screenshot of the panel in light and dark (a `<picture>` that follows the reader's appearance), what it does, install, getting started, updating, uninstalling, privacy, feedback. `DEVELOPMENT.md` has building and the working agreements; `CLAUDE.md` points Claude Code to it. Feedback goes through GitHub issue forms (`.github/ISSUE_TEMPLATE/`): "Something isn't working", which asks for Copy Diagnostics and warns that device names can include the reporter's name, and "Idea or request". Only Marcus can change the repo; anyone can read it, download releases and open issues.
- **README screenshots** are the real panel with made-up devices (USB Microphone, AirPods Pro, MacBook Pro Microphone, Webcam; a "Desk" setup), never Marcus's. A throwaway program builds an `AppModel` with those devices, shows the panel as the key window over a gradient window that covers everything behind it, and captures only that area (`CGWindowListCreateImage`), so nothing else on screen gets in; then the corners are rounded. The first ones were taken on a 1x external monitor; redo them on a Retina screen for sharper images.
- **Don't use SwiftUI's `@State`** (same rule as Tally Cam). On the macOS 27 SDK it's a macro, and its plugin ships only with Xcode, so the build fails with just the Command Line Tools. Keep view state in an `@Observable` object owned by a controller, like `HoverState` and `GeneralSettingsState`. `@AppStorage` is a plain property wrapper and works.

## 12. Milestones

Each one ends with something usable.

1. **The menu.** Icon, panel, device list with icons, click to switch, volume slider, Sound Settings footer, live updates, launch at login. PR includes Copy Diagnostics output and answers to: which devices have settable volume, whether the Input tab deep link works, and what the MacBook mic looks like with the lid closed. After this it replaces the built-in menu for daily use.
   - Answers: every input except the iPhone's Continuity mic has a settable volume (7.3). The MacBook mic stays listed and "alive" with the lid closed (6.2). The Sound pane accepts an `input` deep link anchor (5.3), and Marcus confirmed it lands on the Input tab. Marcus tested everything in the Milestone 1 checklist and it all worked.
2. **Devices tab.** Show/hide, display names, forget.
   - Built on top of the menu bar highlight (macOS 27's expanded interface, 5.1).
3. **Preferred order and setups**, in two stages:
   - **3a. Setups, no switching.** Display triggers, DisplayMonitor, SetupResolver, the Setups tab, the log noting the active setup. Nothing changes the mic yet, so setups can be arranged and docking checked safely.
   - **3b. Automatic switching.** Built: the switch in General and the panel, AutoSwitcher, the panel's Setup line, headsets following the sound output, lid, wake and docking handling. Test with Marcus: dock and undock a few times, close the lid while docked, connect and disconnect the headset in each setup.
4. **Sharing and polish.** Marcus wants to share the repo with his team and let them install it, which became part of this milestone. He chose, of the planned polish, only a dark mode check; the rest moved to BACKLOG.
   - **Installing for teammates:** GitHub releases (11), signed with "Tally Local" (9), with install, update, uninstall and privacy notes at the top of the README. Marcus chose this over Apple-signed releases (needs a Developer ID) and over building from source (needs the Command Line Tools and Terminal).
   - **macOS 27 on Apple silicon only** (3), which Marcus chose over keeping untested fallbacks.
   - **Dark mode check:** the panel, both bubbles and all four Settings tabs rendered in dark mode and reviewed. Settings and the bubbles look right. The panel does too, except that its two switches can turn grey while on: a native switch draws that way in dark mode whenever its window isn't key and the app isn't active (light mode keeps it blue either way). Neither `controlActiveState` nor an explicit tint changes that. The panel is made key when it opens, and the log records whether it became key ("Panel opened at …, key window: …"). It did every time Marcus opened it from the menu bar, which is when the switches drew blue in testing, so they're very likely fine; Marcus chose not to check in dark mode himself. If they ever show grey, draw them in Tally Mic like the slider (BACKLOG).
   - The side-by-side check against the Sound menu happened along the way, through the pixel matching in 5.3 and 7.7.

## 13. Open questions

- Should picking a device by hand also move it to the top of the preferred order? Current answer: no; it turns automatic switching off.
- Share the panel code with Tally Cam as a Swift package instead of copying? Deferred, see BACKLOG.
- Triggers other than a display (a USB dock, Wi-Fi network, time of day)? Deferred, see BACKLOG. A display covers the desk vs laptop case.
