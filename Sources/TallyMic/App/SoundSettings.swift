import AppKit

/// The panel's "Sound Settings…" footer (SPEC 5.3). The Sound pane in System Settings accepts an
/// `input` anchor, which opens it on the Input tab.
enum SoundSettings {
    static let inputURL = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension?input")!

    @MainActor
    static func open() {
        if !NSWorkspace.shared.open(inputURL) {
            Log.error("Couldn't open Sound Settings at \(inputURL)")
        }
    }
}
