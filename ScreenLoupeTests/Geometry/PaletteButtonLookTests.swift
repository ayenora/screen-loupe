import Testing

private func look(
    highlighted: Bool = false, listOpen: Bool = false, picking: Bool = false, toggle: Bool = false, on: Bool = false,
    enabled: Bool = true
) -> PaletteButtonLook {
    PaletteButtonLook.look(
        isHighlighted: highlighted, isListOpen: listOpen, isPicking: picking, isToggle: toggle, isOn: on,
        isEnabled: enabled)
}

struct PaletteButtonLookTests {
    // MARK: At rest

    @Test func aButtonAtRestHasNoFillAndALabelSymbol() {
        #expect(look() == PaletteButtonLook(fill: .none, symbol: .label))
    }

    @Test func aDisabledButtonAtRestHasATertiarySymbol() {
        #expect(look(enabled: false) == PaletteButtonLook(fill: .none, symbol: .tertiary))
    }

    @Test func aToggleThatIsOffLooksAtRest() {
        #expect(look(toggle: true) == PaletteButtonLook(fill: .none, symbol: .label))
        #expect(look(toggle: true, enabled: false) == PaletteButtonLook(fill: .none, symbol: .tertiary))
    }

    // MARK: On

    @Test func aToggleThatIsOnIsFilledWithTheAccent() {
        #expect(
            look(toggle: true, on: true)
                == PaletteButtonLook(fill: .accent(enabled: true), symbol: .onAccent(enabled: true)))
    }

    @Test func aDisabledToggleThatIsOnKeepsItsFillFaded() {
        #expect(
            look(toggle: true, on: true, enabled: false)
                == PaletteButtonLook(fill: .accent(enabled: false), symbol: .onAccent(enabled: false)))
    }

    @Test func aMomentaryButtonWhoseHiddenStateFlippedShowsNothing() {
        #expect(look(on: true) == PaletteButtonLook(fill: .none, symbol: .label))
        #expect(look(on: true, enabled: false) == PaletteButtonLook(fill: .none, symbol: .tertiary))
    }

    // MARK: Pressed

    @Test func pressedListOpenOrPickingShowTheGreyFill() {
        let pressed = PaletteButtonLook(fill: .pressed, symbol: .label)
        #expect(look(highlighted: true) == pressed)
        #expect(look(listOpen: true) == pressed)
        #expect(look(picking: true) == pressed)
    }

    @Test func pressedWhileOnShowsTheGreyFillNotTheAccent() {
        #expect(look(highlighted: true, toggle: true, on: true) == PaletteButtonLook(fill: .pressed, symbol: .label))
        #expect(look(listOpen: true, toggle: true, on: true) == PaletteButtonLook(fill: .pressed, symbol: .label))
    }

    @Test func aDisabledPressedButtonHasATertiarySymbol() {
        #expect(look(picking: true, enabled: false) == PaletteButtonLook(fill: .pressed, symbol: .tertiary))
        #expect(
            look(highlighted: true, toggle: true, on: true, enabled: false)
                == PaletteButtonLook(fill: .pressed, symbol: .tertiary))
    }

    // MARK: The whole table

    /// All 64 combinations, by the rules rather than by the cases above.
    @Test func everyCombinationFollowsTheRules() {
        let bools = [false, true]
        var count = 0
        for highlighted in bools {
            for listOpen in bools {
                for picking in bools {
                    for toggle in bools {
                        for on in bools {
                            for enabled in bools {
                                let result = look(
                                    highlighted: highlighted, listOpen: listOpen, picking: picking, toggle: toggle,
                                    on: on, enabled: enabled)
                                let accent = result.fill == .accent(enabled: enabled)
                                #expect(accent == (toggle && on && !highlighted && !listOpen && !picking))
                                // A near-white symbol only ever sits on the accent.
                                #expect(accent == (result.symbol == .onAccent(enabled: enabled)))
                                let pressed = highlighted || listOpen || picking
                                #expect((result.fill == .pressed) == pressed)
                                #expect((result.fill == .none) == (!pressed && !(toggle && on)))
                                // Off the accent, the symbol shows only whether the button is enabled.
                                if !accent { #expect(result.symbol == (enabled ? .label : .tertiary)) }
                                count += 1
                            }
                        }
                    }
                }
            }
        }
        #expect(count == 64)
    }
}
