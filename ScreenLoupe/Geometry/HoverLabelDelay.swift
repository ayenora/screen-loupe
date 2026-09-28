import Foundation

/// When the studio palette (docs/product.md, The palette) and a frame's tab name the button under
/// the pointer, as the system's tooltips do: after a rest on the button, or at once while the
/// pointer goes from button to button soon after a name showed.
enum HoverLabelDelay {
    /// How long the pointer rests on a button before its name shows.
    static let rest: TimeInterval = 0.5
    /// How long after a name went the next button's name still shows at once.
    static let grace: TimeInterval = 0.5

    /// The wait before the name of the button the pointer entered at `now` shows. `lastHidden` is
    /// when a shown name last went as the pointer left its button, in seconds of the same clock;
    /// `nil` when none has shown since the buttons showed or since a click.
    static func delay(at now: TimeInterval, lastHidden: TimeInterval?) -> TimeInterval {
        guard let lastHidden, now - lastHidden <= grace else { return rest }
        return 0
    }
}

/// Which button the hover label is for, and when a shown name last went (`ButtonNameLabel`). An
/// exit from a button the pointer has already left for another changes nothing: where buttons
/// touch, the next one's enter can come first. A click or hiding ends it all: the next button
/// waits the full rest.
struct HoverLabelState<Button: Hashable> {
    /// The button the pointer last entered, until it leaves it, a click or hiding.
    private(set) var hovered: Button?
    /// When a shown name last went as the pointer left its button (`HoverLabelDelay.delay`).
    private(set) var hiddenAt: TimeInterval?

    /// What follows an enter, once any label or wait has gone.
    enum Next: Equatable {
        case show
        case wait(TimeInterval)
    }

    /// The pointer entered `button` at `now`; `labelShown`: a name shows, and goes now.
    mutating func enter(_ button: Button, at now: TimeInterval, labelShown: Bool) -> Next {
        labelGoes(at: now, labelShown: labelShown)
        hovered = button
        let delay = HoverLabelDelay.delay(at: now, lastHidden: hiddenAt)
        return delay > 0 ? .wait(delay) : .show
    }

    /// The pointer left `button` at `now`: whether the label, or its wait, goes. Not for a stale exit.
    mutating func exit(_ button: Button, at now: TimeInterval, labelShown: Bool) -> Bool {
        guard hovered == button else { return false }
        hovered = nil
        labelGoes(at: now, labelShown: labelShown)
        return true
    }

    /// A click or hiding.
    mutating func end() {
        hovered = nil
        hiddenAt = nil
    }

    private mutating func labelGoes(at now: TimeInterval, labelShown: Bool) {
        if labelShown { hiddenAt = now }
    }
}
