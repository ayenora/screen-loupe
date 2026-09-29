/// How a studio palette button draws: the toolbar's on and
/// pressed look. Pressed, with its list open or while its picker runs, a grey fill under the
/// label-coloured symbol; a toggle that is on, the accent colour under a near-white symbol, both
/// faded while the button is off, as the toolbar's are. A momentary button's `state` flips on every
/// click too, though AppKit doesn't show it: only a toggle's is drawn. The view maps the looks to
/// colours.
struct PaletteButtonLook: Equatable, Sendable {
    enum Fill: Equatable, Sendable {
        case none
        /// The grey pressed fill.
        case pressed
        /// The accent colour; faded when not `enabled`.
        case accent(enabled: Bool)
    }

    enum Symbol: Equatable, Sendable {
        /// The label colour.
        case label
        /// The tertiary label colour: a disabled button.
        case tertiary
        /// Near white, on the accent fill; faded when not `enabled`.
        case onAccent(enabled: Bool)
    }

    var fill: Fill
    var symbol: Symbol

    /// `isOn`: the button's `state` is on.
    static func look(
        isHighlighted: Bool, isListOpen: Bool, isPicking: Bool, isToggle: Bool, isOn: Bool, isEnabled: Bool
    ) -> PaletteButtonLook {
        if isHighlighted || isListOpen || isPicking {
            return PaletteButtonLook(fill: .pressed, symbol: isEnabled ? .label : .tertiary)
        }
        if isToggle && isOn {
            return PaletteButtonLook(fill: .accent(enabled: isEnabled), symbol: .onAccent(enabled: isEnabled))
        }
        return PaletteButtonLook(fill: .none, symbol: isEnabled ? .label : .tertiary)
    }
}
