/// Which key combinations a global shortcut may use.
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

    /// The shortcut an action added since the settings were saved starts with: its default, unless
    /// one of the saved shortcuts already has the same keys. Then the user's choice stays and the new
    /// action starts unassigned, as a cleared one, rather than both registering the same keys.
    static func newDefault<Keys>(_ fallback: Keys?, saved: [Keys?], sameKeys: (Keys, Keys) -> Bool) -> Keys? {
        guard let fallback, !saved.contains(where: { $0.map { sameKeys($0, fallback) } ?? false }) else {
            return nil
        }
        return fallback
    }

    /// What a registered hot key's id stands for: one of the app's actions, by its index, or a
    /// shortcut an edition added, by its index among those (`GlobalShortcuts.add`).
    enum Target: Equatable, Sendable {
        case action(Int)
        case added(Int)
    }

    /// Where the added shortcuts' ids start, well after the app's own actions'.
    static let firstAddedID = 1000

    /// The id the added shortcut at `index` is registered with.
    static func id(ofAdded index: Int) -> Int { firstAddedID + index }

    /// What `id` stands for among `actions` app actions and `added` added shortcuts; `nil` for an id
    /// that is neither.
    static func target(ofID id: Int, actions: Int, added: Int) -> Target? {
        if (0..<actions).contains(id) { return .action(id) }
        let index = id - firstAddedID
        return (0..<added).contains(index) ? .added(index) : nil
    }
}
