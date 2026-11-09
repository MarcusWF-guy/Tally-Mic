# Working on Tally Mic

Tally Mic is a small native Mac app: Swift, SwiftUI and AppKit, built with Swift Package Manager and Apple's Command Line Tools. No Xcode project, no dependencies. Sibling to **Tally Cam** (formerly Fettle Cam, originally Keyframe), the webcam controller, with the same look and panel code.

Bug reports and ideas go in [issues](https://github.com/MarcusWF-guy/Tally-Mic/issues).

## Docs

| File | What's in it |
|---|---|
| `README.md` | The public page: what Tally Mic does, how to install it. |
| `DEVELOPMENT.md` | This. Building it, and how we work on it. |
| `SPEC.md` | Exactly how the app is built. Source of truth. |
| `BACKLOG.md` | Deferred ideas and why they were deferred. |
| `CLAUDE.md` | Points Claude Code here. |

## Build it yourself

You need a Mac with Apple silicon on macOS 27, and Apple's Command Line Tools (`xcode-select --install` in Terminal).

```bash
git clone https://github.com/MarcusWF-guy/Tally-Mic.git
cd Tally-Mic
./scripts/install.sh
```

`install.sh` builds Tally Mic, replaces `/Applications/Tally Mic.app` and opens it. The first build creates a self-signed "Tally Local" code-signing certificate in your login keychain, and macOS asks for your Mac password once. Signing every build with the same certificate keeps launch at login and Accessibility working across rebuilds (SPEC 9).

`swift test` runs the tests. SPEC 11 has the rest: the build scripts, the tests, how to see the real UI without opening the app, and why there's no SwiftUI `@State`.

## For AI agents picking this up

Read this file, then SPEC, then BACKLOG. That's the whole project. SPEC wins if anything disagrees.

**Working agreements**

- Never commit to `main`. One branch per change, open a PR.
- Before pushing to an existing PR, check it's still open (`gh pr view`). If it's merged, open a new PR.
- PR descriptions explain what changed and why in plain language, then end with a **"What Marcus needs to do"** checklist: every step, in order. Merging, running the install script, anything to approve, and exactly what to test. Marcus isn't a developer, so be specific.
- Ask Marcus to test instead of guessing or brute-forcing. Give short, concrete steps ("Unplug the headset receiver, plug it back in, tell me which mic is checked").
- Build and test in a **local** Claude Code session on Marcus's Mac. Cloud sessions can't build Mac apps or see audio devices.
- Keep it native and light: Swift, SwiftUI/AppKit, no Electron, no web views, no third-party UI kits.
- It has to look identical to Apple's Sound menu. Copy the panel shell and row components from the Tally Cam repo, and compare screenshots side by side.
- Behavior change? Update SPEC.md in the same PR. Deferring something? Add it to BACKLOG.md.
- The repo is public. Keep personal details out of code, tests and screenshots: made-up device names and IDs in tests, made-up devices in README images (SPEC 11).

## Marcus's setup

### One time

If you already set up Tally Cam, steps 1 and 2 are done.

1. **Command Line Tools.** Terminal: `xcode-select --install`.
2. **Homebrew** and **GitHub CLI.** `brew install gh`, then `gh auth login`.
3. **Signing certificate.** The first build creates the "Tally Local" certificate and asks for your Mac password once. Releases are signed with it too, so keep it: a new one would make everyone who installed Tally Mic give it its permissions again after updating.

### Day to day

- After merging a PR: `./scripts/install.sh` rebuilds and relaunches. Claude runs it, and it's always in the PR checklist.
- **Releasing:** bump `CFBundleShortVersionString` in `Resources/Info.plist` in a PR. After it's merged, run `./scripts/release.sh` on `main`. It builds, zips and publishes the release on GitHub, and the README's download button picks it up (SPEC 11).
- Settings live in `~/Library/Application Support/Tally Mic/config.json`.
- Logs live in `~/Library/Logs/Tally Mic/`.
- Something weird? Settings > General > Copy Diagnostics, and paste it to Claude. (Claude can get the same report itself with `"/Applications/Tally Mic.app/Contents/MacOS/TallyMic" --diagnostics`.)
- **README screenshots** show the real panel with made-up devices, captured by a throwaway program over a gradient window (SPEC 11). Redo them when the panel changes, ideally on a Retina screen.
