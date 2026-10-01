import AppKit

/// The One Window menu the ▾ beside the palette's One Window button pops up, a native menu as the
/// Viewer toolbar's ▾ buttons pop up: One Window Shadow, checked while on, a separator, Pick Another
/// Window and End One Window. Open in every mode, so the shadow can be set before a window is
/// picked; the items that don't apply are disabled by `validateMenuItem` as the menu opens
/// (`OneWindowMode.canPickAnother`, `canEnd`). End One Window shows no shortcut: Escape cancels
/// only a picking, as the picker's hint says. The menu's items target this object, which reads the
/// mode and the setting live and calls back.
@MainActor
final class StudioOneWindowMenu: NSObject, NSMenuItemValidation {
    private let mode: () -> OneWindowMode
    private let windowShadow: () -> Bool
    private let toggleWindowShadow: () -> Void
    private let pickAnother: () -> Void
    private let end: () -> Void

    init(
        mode: @escaping () -> OneWindowMode, windowShadow: @escaping () -> Bool,
        toggleWindowShadow: @escaping () -> Void, pickAnother: @escaping () -> Void, end: @escaping () -> Void
    ) {
        self.mode = mode
        self.windowShadow = windowShadow
        self.toggleWindowShadow = toggleWindowShadow
        self.pickAnother = pickAnother
        self.end = end
    }

    /// A new menu of the three items, targeting this object.
    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector) {
            menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = self
        }
        add("One Window Shadow", #selector(shadowChosen(_:)))
        menu.addItem(.separator())
        add("Pick Another Window", #selector(pickAnotherChosen(_:)))
        add("End One Window", #selector(endChosen(_:)))
        return menu
    }

    @objc private func shadowChosen(_ sender: NSMenuItem) { toggleWindowShadow() }
    @objc private func pickAnotherChosen(_ sender: NSMenuItem) { pickAnother() }
    @objc private func endChosen(_ sender: NSMenuItem) { end() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(shadowChosen(_:)):
            // A setting: enabled in every mode.
            menuItem.state = windowShadow() ? .on : .off
            return true
        case #selector(pickAnotherChosen(_:)): return mode().canPickAnother
        case #selector(endChosen(_:)): return mode().canEnd
        default: return true
        }
    }
}
