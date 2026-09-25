/// Which key combinations a global shortcut may use (docs/product.md, Settings › Shortcuts).
enum ShortcutRules {
    /// The modifiers of a combination.
    struct Modifiers: Equatable, Sendable {
        var control = false
        var option = false
        var shift = false
        var command = false

        var isEmpty: Bool { !control && !option && !shift && !command }
    }

    /// A shortcut needs ⌃, or ⌥ with ⌘: ⌘ alone or with ⇧ would take standard shortcuts away from
    /// every app, and macOS rejects ⌥ or ⌥⇧ alone. An action that `allowsLoneFunctionKey` (Freeze)
    /// may also be F13–F19 alone, so no modifier reaches the app the mouse is held down in.
    static func isAllowed(_ modifiers: Modifiers, isHighFunctionKey: Bool, allowsLoneFunctionKey: Bool) -> Bool {
        if modifiers.control || (modifiers.option && modifiers.command) { return true }
        return allowsLoneFunctionKey && isHighFunctionKey && modifiers.isEmpty
    }
}
