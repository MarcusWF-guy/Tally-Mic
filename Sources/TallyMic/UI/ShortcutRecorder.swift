import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A box for setting a keyboard shortcut (SPEC 7.6): click it, then type the keys. Esc cancels,
/// Delete clears. Keys need ⌘, ⌥ or ⌃ unless they're function keys; anything else beeps.
struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: Shortcut?
    let label: String
    let onChange: (Shortcut?) -> Void
    let onRecordingChange: (Bool) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.setAccessibilityLabel(label)
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.shortcut = shortcut
        button.onChange = onChange
        button.onRecordingChange = onRecordingChange
    }
}

final class ShortcutRecorderButton: NSButton {
    var shortcut: Shortcut? { didSet { if shortcut != oldValue { updateTitle() } } }
    var onChange: ((Shortcut?) -> Void)?
    var onRecordingChange: ((Bool) -> Void)?
    private var isRecording = false

    init() {
        super.init(frame: .zero)
        bezelStyle = .push
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(clicked)
        updateTitle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var acceptsFirstResponder: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 150, height: super.intrinsicContentSize.height)
    }

    @objc private func clicked() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        isRecording = true
        window?.makeFirstResponder(self)
        onRecordingChange?(true)
        updateTitle()
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        onRecordingChange?(false)
        updateTitle()
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }

    // Shortcuts with ⌘ arrive here before keyDown.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        record(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return super.keyDown(with: event) }
        record(event)
    }

    private func record(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let keyCode = UInt32(event.keyCode)
        if flags.isEmpty, keyCode == UInt32(kVK_Escape) {
            stopRecording()
            return
        }
        if flags.isEmpty, keyCode == UInt32(kVK_Delete) || keyCode == UInt32(kVK_ForwardDelete) {
            onChange?(nil)
            stopRecording()
            return
        }
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        guard Shortcut.isAllowed(keyCode: keyCode, modifiers: modifiers) else {
            NSSound.beep()
            return
        }
        onChange?(Shortcut(keyCode: keyCode, modifiers: modifiers))
        stopRecording()
    }

    private func updateTitle() {
        let name = shortcut?.displayName
        title = isRecording ? "Type Shortcut…" : name ?? "Record Shortcut"
        contentTintColor = name == nil && !isRecording ? .secondaryLabelColor : nil
        setAccessibilityValue(isRecording ? "Recording" : name ?? "None")
    }
}
