import AppKit
import Carbon.HIToolbox
import Observation

/// A key combination for a global shortcut.
struct Shortcut: Codable, Hashable, Sendable {
    /// The virtual key code (`kVK_…`).
    var keyCode: UInt32
    /// `NSEvent.ModifierFlags` raw value: ⌃, ⌥, ⇧ and ⌘ only.
    var modifiers: UInt
    /// The key as shown, such as `L` or `F5`.
    var key: String

    init(keyCode: Int, modifiers: NSEvent.ModifierFlags, key: String) {
        self.keyCode = UInt32(keyCode)
        self.modifiers = modifiers.intersection([.control, .option, .shift, .command]).rawValue
        self.key = key
    }

    var modifierFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    /// The same physical keys, whatever layout labelled them.
    func hasSameKeys(as other: Shortcut) -> Bool {
        keyCode == other.keyCode && modifiers == other.modifiers
    }

    /// `⌃⌥⌘L`, in the order macOS menus use.
    var displayString: String {
        let flags = modifierFlags
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text + key
    }

    fileprivate var carbonModifiers: UInt32 {
        let flags = modifierFlags
        var result = 0
        if flags.contains(.control) { result |= controlKey }
        if flags.contains(.option) { result |= optionKey }
        if flags.contains(.shift) { result |= shiftKey }
        if flags.contains(.command) { result |= cmdKey }
        return UInt32(result)
    }
}

/// The global shortcuts (docs/product.md, Global shortcuts). A cleared shortcut is `nil`, saved as
/// `null`, so it stays cleared; a key missing from saved settings (an action added later) gets its
/// default.
struct Shortcuts: Codable, Equatable, Sendable {
    var toggleCaptureArea: Shortcut? = Shortcut(
        keyCode: kVK_ANSI_L, modifiers: [.control, .option, .command], key: "L")
    var toggleViewer: Shortcut? = Shortcut(keyCode: kVK_ANSI_V, modifiers: [.control, .option, .command], key: "V")
    var copyView: Shortcut? = Shortcut(keyCode: kVK_ANSI_C, modifiers: [.control, .option, .command], key: "C")
    var copySource: Shortcut? = Shortcut(
        keyCode: kVK_ANSI_C, modifiers: [.control, .option, .shift, .command], key: "C")
    /// F13 alone: no modifier reaches the app the mouse is held down in.
    var toggleFreeze: Shortcut? = Shortcut(keyCode: kVK_F13, modifiers: [], key: "F13")
    var pickWindow: Shortcut? = Shortcut(keyCode: kVK_ANSI_W, modifiers: [.control, .option, .command], key: "W")

    init() {}

    private enum CodingKeys: String, CodingKey {
        case toggleCaptureArea, toggleViewer, copyView, copySource, toggleFreeze, pickWindow
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Shortcuts()
        func shortcut(_ key: CodingKeys, _ fallback: Shortcut?) -> Shortcut? {
            guard c.contains(key) else { return fallback }
            if (try? c.decodeNil(forKey: key)) == true { return nil }
            return c.value(key, or: fallback)
        }
        toggleCaptureArea = shortcut(.toggleCaptureArea, d.toggleCaptureArea)
        toggleViewer = shortcut(.toggleViewer, d.toggleViewer)
        copyView = shortcut(.copyView, d.copyView)
        copySource = shortcut(.copySource, d.copySource)
        toggleFreeze = shortcut(.toggleFreeze, d.toggleFreeze)
        pickWindow = shortcut(.pickWindow, d.pickWindow)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(toggleCaptureArea, forKey: .toggleCaptureArea)
        try c.encode(toggleViewer, forKey: .toggleViewer)
        try c.encode(copyView, forKey: .copyView)
        try c.encode(copySource, forKey: .copySource)
        try c.encode(toggleFreeze, forKey: .toggleFreeze)
        try c.encode(pickWindow, forKey: .pickWindow)
    }
}

enum ShortcutAction: CaseIterable, Sendable {
    case toggleCaptureArea, toggleViewer, copyView, copySource, toggleFreeze, pickWindow

    var title: String {
        switch self {
        case .toggleCaptureArea: "Show / Hide Capture Area"
        case .toggleViewer: "Show / Hide Viewer"
        case .copyView: "Copy View"
        case .copySource: "Copy Source"
        case .toggleFreeze: "Freeze / Resume Viewer"
        case .pickWindow: "Fit Capture Area to Window"
        }
    }

    /// Freeze may be F13–F19 alone (`ShortcutRules`).
    var allowsLoneFunctionKey: Bool { self == .toggleFreeze }

    var keyPath: WritableKeyPath<Shortcuts, Shortcut?> {
        switch self {
        case .toggleCaptureArea: \.toggleCaptureArea
        case .toggleViewer: \.toggleViewer
        case .copyView: \.copyView
        case .copySource: \.copySource
        case .toggleFreeze: \.toggleFreeze
        case .pickWindow: \.pickWindow
        }
    }
}

/// Registers the shortcuts with Carbon's `RegisterEventHotKey`, which works from any app and needs
/// no Accessibility permission (docs/design.md §4).
@MainActor
@Observable
final class GlobalShortcuts {
    @ObservationIgnored var onAction: ((ShortcutAction) -> Void)?
    /// Shortcuts macOS refused: taken by the system or another app, or not allowed.
    private(set) var failed: Set<ShortcutAction> = []

    @ObservationIgnored private var shortcuts = Shortcuts()
    @ObservationIgnored private var registered: [EventHotKeyRef] = []
    @ObservationIgnored private var handler: EventHandlerRef?
    /// "SLup": tells our hot keys apart from any other in the app.
    private static let signature: OSType = 0x534C_7570

    /// While a shortcut is being recorded in Settings, so pressing a taken combination records it
    /// instead of running it.
    var isSuspended = false {
        didSet { if isSuspended != oldValue { registerAll() } }
    }

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                var id = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &id)
                guard status == noErr, let userData else { return status }
                // Carbon delivers hot keys on the main thread.
                MainActor.assumeIsolated {
                    Unmanaged<GlobalShortcuts>.fromOpaque(userData).takeUnretainedValue().fire(id)
                }
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func register(_ shortcuts: Shortcuts) {
        self.shortcuts = shortcuts
        registerAll()
    }

    private func registerAll() {
        registered.forEach { UnregisterEventHotKey($0) }
        registered.removeAll()
        guard !isSuspended else { return }
        var failed: Set<ShortcutAction> = []
        for (index, action) in ShortcutAction.allCases.enumerated() {
            guard let shortcut = shortcuts[keyPath: action.keyPath] else { continue }
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(index))
            if RegisterEventHotKey(
                shortcut.keyCode, shortcut.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr,
                let ref
            {
                registered.append(ref)
            } else {
                failed.insert(action)
            }
        }
        self.failed = failed
    }

    private func fire(_ id: EventHotKeyID) {
        let actions = ShortcutAction.allCases
        guard id.signature == Self.signature, Int(id.id) < actions.count else { return }
        onAction?(actions[Int(id.id)])
    }
}
