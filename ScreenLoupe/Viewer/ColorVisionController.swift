import Foundation

/// The Viewer's colour vision simulation: the chosen mode and whether it is split with normal
/// vision, kept in the settings, and whether it is on, which isn't kept (`ColorVisionChoice`).
@MainActor
final class ColorVisionController {
    private let settings: SettingsStore
    private(set) var isOn = false
    private var observers: [() -> Void] = []

    init(settings: SettingsStore) {
        self.settings = settings
    }

    /// The mode the eye button turns on and off.
    var mode: ColorVisionMode { settings.settings.colorVisionMode }
    /// Split with Normal Vision, remembered while the simulation is off: the menu item's check.
    var isSplit: Bool { settings.settings.colorVisionSplit }
    /// Whether the Viewer shows the split now: split and on.
    var showsSplit: Bool { choice.showsSplit }
    /// The mode simulated now, or `nil`.
    var active: ColorVisionMode? { choice.active }

    /// The simulation shown now — the active mode's matrix and label, or what `supplied` gives for
    /// it — or `nil` while off.
    var simulation: ColorVisionSimulation? {
        active.map { supplied?($0) ?? ColorVisionSimulation(mode: $0) }
    }

    /// A simulation an edition supplies for a mode in place of the mode's own; `nil` for a mode it
    /// leaves as it is. `nil`, the default, supplies none.
    var supplied: ((ColorVisionMode) -> ColorVisionSimulation?)? {
        didSet { suppliedChanged() }
    }

    /// Shows again what `supplied` gives, after it changed.
    func suppliedChanged() {
        for observer in observers { observer() }
    }

    private var choice: ColorVisionChoice { ColorVisionChoice(mode: mode, isOn: isOn, isSplit: isSplit) }

    /// Calls `observer` after every change of the mode, of whether it is on or split, or of what is
    /// supplied.
    func observe(_ observer: @escaping () -> Void) {
        observers.append(observer)
    }

    /// The eye button and View › Color Vision › Simulate Color Vision.
    func toggle() {
        choose(choice.toggled())
    }

    /// A mode chosen in the eye button's ▾ or the View menu.
    func turnOn(_ mode: ColorVisionMode) {
        choose(choice.turnedOn(mode))
    }

    /// View › Color Vision › Split with Normal Vision and its place in the ▾ and the overflow.
    func toggleSplit() {
        choose(choice.splitToggled())
    }

    /// Ends the split, the simulation staying as it is: a reference layer chose Split.
    func endSplit() {
        choose(choice.withoutSplit())
    }

    private func choose(_ next: ColorVisionChoice) {
        guard next != choice else { return }
        settings.update {
            $0.colorVisionMode = next.mode
            $0.colorVisionSplit = next.isSplit
        }
        isOn = next.isOn
        for observer in observers { observer() }
    }
}
