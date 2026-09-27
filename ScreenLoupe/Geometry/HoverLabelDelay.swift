import Foundation

/// When the studio palette names the button under the pointer (docs/product.md, The palette), as
/// the system's tooltips do: after a rest on the button, or at once while the pointer goes from
/// button to button soon after a name showed.
enum HoverLabelDelay {
    /// How long the pointer rests on a button before its name shows.
    static let rest: TimeInterval = 0.5
    /// How long after a name went the next button's name still shows at once.
    static let grace: TimeInterval = 0.5

    /// The wait before the name of the button the pointer entered at `now` shows. `lastHidden` is
    /// when a shown name last went as the pointer left its button, in seconds of the same clock;
    /// `nil` when none has shown since the palette showed or since a click.
    static func delay(at now: TimeInterval, lastHidden: TimeInterval?) -> TimeInterval {
        guard let lastHidden, now - lastHidden <= grace else { return rest }
        return 0
    }
}
