import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A button that records a global shortcut: click it and press the keys. Escape cancels, Delete
/// clears. Which combinations are allowed is `ShortcutRules`.
struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: Shortcut?
    /// F13–F19 alone is allowed too (Freeze).
    var allowsLoneFunctionKey = false
    /// Called with `true` when recording starts and `false` when it ends.
    let onRecording: (Bool) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        ShortcutRecorderButton()
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.shortcut = shortcut
        button.onChange = { shortcut = $0 }
        button.onRecording = onRecording
        button.allowsLoneFunctionKey = allowsLoneFunctionKey
    }
}

final class ShortcutRecorderButton: NSButton {
    var shortcut: Shortcut? { didSet { updateTitle() } }
    var onChange: ((Shortcut?) -> Void)?
    var onRecording: ((Bool) -> Void)?
    var allowsLoneFunctionKey = false

    private var windowObserver: NSObjectProtocol?

    private var isRecording = false {
        didSet {
            guard isRecording != oldValue else { return }
            updateTitle()
            onRecording?(isRecording)
        }
    }

    init() {
        super.init(frame: .zero)
        bezelStyle = .push
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(startRecording)
        widthAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
        updateTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func updateTitle() {
        title = isRecording ? "Type Shortcut…" : shortcut?.displayString ?? "Record Shortcut"
    }

    @objc private func startRecording() {
        isRecording = true
        window?.makeFirstResponder(self)
    }

    override var acceptsFirstResponder: Bool { true }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    /// Closing Settings or switching to another app ends recording, so the global shortcuts don't
    /// stay suspended.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
        windowObserver = nil
        guard let window else {
            isRecording = false
            return
        }
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.isRecording = false }
        }
    }

    /// Combinations with ⌘ arrive here before `keyDown`.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        record(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return super.keyDown(with: event) }
        record(event)
    }

    private func record(_ event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_Escape:
            isRecording = false
            return
        case kVK_Delete, kVK_ForwardDelete:
            onChange?(nil)
            isRecording = false
            return
        default:
            break
        }
        let modifiers = event.modifierFlags.intersection([.control, .option, .shift, .command])
        let allowed = ShortcutRules.isAllowed(
            ShortcutRules.Modifiers(
                control: modifiers.contains(.control), option: modifiers.contains(.option),
                shift: modifiers.contains(.shift), command: modifiers.contains(.command)),
            isHighFunctionKey: Self.highFunctionKeys.contains(Int(event.keyCode)),
            allowsLoneFunctionKey: allowsLoneFunctionKey)
        guard allowed, let key = Self.keyName(event) else {
            NSSound.beep()
            return
        }
        onChange?(Shortcut(keyCode: Int(event.keyCode), modifiers: modifiers, key: key))
        isRecording = false
    }

    private static let names: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7",
        kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13",
        kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19",
    ]

    /// F13–F19: no Mac shortcut uses them, so one alone can be a global shortcut.
    private static let highFunctionKeys: Set<Int> = [kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19]

    /// The key as the current Latin keyboard layout labels it, so `L` stays `L` while a Cyrillic
    /// layout is active.
    private static func keyName(_ event: NSEvent) -> String? {
        if let name = names[Int(event.keyCode)] { return name }
        guard let characters = latinCharacter(forKeyCode: event.keyCode) ?? event.charactersIgnoringModifiers,
            let scalar = characters.unicodeScalars.first, !CharacterSet.controlCharacters.contains(scalar)
        else { return nil }
        return characters.uppercased()
    }

    private static func latinCharacter(forKeyCode keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
            let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        var deadKeys: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout in
            UCKeyTranslate(
                layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, characters.count, &length, &characters)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }
}
