import CoreGraphics

/// How a studio palette button draws: the toolbar's on and
/// pressed look. Pressed, with its menu open or while its picker runs, a grey fill under the
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

/// The ▾ beside a palette button, laid out and highlighted as `NSToolbar` does the ▾ of a toolbar
/// item (measured on macOS 27 from a real toolbar's layers: a 16 pt `.toolbar`-bezel ▾ beside a
/// button, its grey pressed capsule as tall as the button's own fill — 20 pt for a 24 pt button,
/// 24 pt for a 28 pt one — 21 and 24 pt wide, centred on the ▾, so it reaches past the ▾ on both
/// sides and meets the button's fill, overlapping it by 2 pt). The ▾ takes the mouse only in its
/// own slot; its view is as wide as the highlight, so the highlight is drawn inside it.
enum PaletteMenuButton {
    /// The ▾'s own width, and its hit slot: the toolbar's.
    static let slotWidth: CGFloat = 16

    /// The highlight's width beside a button whose fill is `fillHeight` tall: as tall as that fill,
    /// so a circle or a square, and at least the slot and 5 pt.
    static func fillWidth(fillHeight: CGFloat) -> CGFloat {
        max(fillHeight, slotWidth + 5)
    }

    /// How far the ▾'s view, as wide as its highlight, reaches past its slot on each side: over the
    /// button left of it, and past the row's end on the right.
    static func overhang(fillHeight: CGFloat) -> CGFloat {
        (fillWidth(fillHeight: fillHeight) - slotWidth) / 2
    }

    /// The ▾'s slot in its view's `frame`: the middle `slotWidth`, as tall as the frame.
    static func hitSlot(in frame: CGRect) -> CGRect {
        frame.insetBy(dx: max(0, (frame.width - slotWidth) / 2), dy: 0)
    }

    /// The width of a button `buttonWidth` wide and its ▾ side by side: the ▾'s view overlaps the
    /// button by the overhang and reaches as far past the slot on the right.
    static func rowWidth(buttonWidth: CGFloat, fillHeight: CGFloat) -> CGFloat {
        buttonWidth + slotWidth + overhang(fillHeight: fillHeight)
    }
}
