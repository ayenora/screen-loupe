import Foundation

/// The Viewer's colour vision simulation: the chosen mode, kept in the settings, and whether it is
/// on, which isn't kept (`ColorVisionChoice`).
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
    /// The mode simulated now, or `nil`.
    var active: ColorVisionMode? { choice.active }

    private var choice: ColorVisionChoice { ColorVisionChoice(mode: mode, isOn: isOn) }

    /// Calls `observer` after every change of the mode or of whether it is on.
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

    private func choose(_ next: ColorVisionChoice) {
        guard next != choice else { return }
        settings.update { $0.colorVisionMode = next.mode }
        isOn = next.isOn
        for observer in observers { observer() }
    }
}
