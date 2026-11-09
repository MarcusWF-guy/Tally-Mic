import AppKit

// `TallyMic --diagnostics` prints the Copy Diagnostics report and quits, for debugging from
// Terminal (SPEC 10). It reads the system without changing anything.
if CommandLine.arguments.contains("--diagnostics") {
    MainActor.assumeIsolated { print(Diagnostics.report(Diagnostics.current())) }
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // Info.plist sets LSUIElement too; this covers running the bare binary during development.
    app.setActivationPolicy(.accessory)
    app.run()
}
