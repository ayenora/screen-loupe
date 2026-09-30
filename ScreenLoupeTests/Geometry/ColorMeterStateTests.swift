import CoreGraphics
import Foundation
import Testing

struct ColorMeterStateTests {
    /// A distinct colour for each `n`, picked at (n, n).
    private func color(_ n: Int) -> PickedColor {
        PickedColor(
            hex: String(format: "#%06X", n), nativeValues: "0.000 0.000 \(n)", nativeSpaceName: "Display P3", x: n,
            y: n)
    }

    /// A state with `count` recent colours, `color(count)` newest.
    private func state(recent count: Int) -> ColorMeterState {
        var state = ColorMeterState()
        for n in 0..<count { state.pick(color(n + 1)) }
        return state
    }

    /// Fills `slot` with `color` by a click on the image while it is the target, and drops the target.
    private func fill(_ slot: ColorMeterState.Slot, with color: PickedColor, in state: inout ColorMeterState) {
        state.clickContrast(slot)
        state.pick(color)
        #expect(state.clearTarget() == true)
    }

    /// Picks `color` and adds it to the favourites from Recent.
    private func favorite(_ color: PickedColor, in state: inout ColorMeterState) {
        state.pick(color)
        #expect(state.addToFavorites(recent: 0) == true)
    }

    // MARK: Picked colours

    @Test func aPickedColourKeepsItsSampleNativeValueAndPosition() {
        let sample = ColorSample(
            red: 255, green: 0, blue: 0, alpha: 128, colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!)
        let picked = PickedColor(sample, x: 64, y: 96)
        #expect(picked.hex == "#FF000080")
        #expect(picked.nativeValues == "1.000 0.000 0.000")
        #expect(picked.nativeSpaceName == "Display P3")
        #expect(picked.x == 64 && picked.y == 96)
        #expect(picked.sample.alpha == sample.alpha)
        #expect(picked.sample.cssRGB == sample.cssRGB)
    }

    @Test func aPickedColourGivesEveryFormatExactlyAsTheLivePixel() throws {
        // A Display P3 pixel whose sRGB value isn't a whole 8-bit step, and a translucent one.
        let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
        for live in [
            ColorSample(red: 24, green: 130, blue: 201, colorSpace: p3),
            ColorSample(red: 250, green: 12, blue: 99, alpha: 77, colorSpace: p3, spaceName: "Studio Display"),
        ] {
            let picked = PickedColor(live, x: 3, y: 4)
            let kept = try JSONDecoder().decode(PickedColor.self, from: JSONEncoder().encode(picked))
            for color in [picked, kept] {
                #expect(color.sample == live)
                #expect(color.sample.hex == live.hex)
                #expect(color.sample.cssRGB == live.cssRGB)
                #expect(color.sample.swiftUI == live.swiftUI)
                #expect(color.sample.appKit == live.appKit)
                #expect(color.sample.nativeValues == live.nativeValues)
                #expect(color.sample.nativeSpaceName == live.nativeSpaceName)
            }
        }
    }

    @Test func aColourSavedWithItsHexOnlyComesBackFromIt() throws {
        let old =
            ##"{"hex":"#FF000080","nativeValues":"1.000 0.000 0.000","nativeSpaceName":"Display P3","x":5,"y":6}"##
        let color = try JSONDecoder().decode(PickedColor.self, from: Data(old.utf8))
        #expect(color.hex == "#FF000080")
        #expect(color.nativeValues == "1.000 0.000 0.000")
        #expect(color.nativeSpaceName == "Display P3")
        #expect(color.x == 5 && color.y == 6)
        #expect(color.native == nil && color.srgb == nil && color.alpha == nil)
        #expect(color.sample == ColorSample(srgbHex: "#FF000080"))
    }

    @Test func unreadableComponentsFallBackToTheHex() throws {
        let json =
            ##"{"hex":"#0A6FE0","nativeValues":"0 0 0","nativeSpaceName":"sRGB","x":0,"y":0,"native":"x","srgb":[0.1,0.2],"alpha":1}"##
        let color = try JSONDecoder().decode(PickedColor.self, from: Data(json.utf8))
        #expect(color.native == nil)
        #expect(color.srgb == [0.1, 0.2])
        #expect(color.sample == ColorSample(srgbHex: "#0A6FE0"))
    }

    @Test func todaysSavedRecentListStillDecodes() throws {
        let old =
            ##"[{"hex":"#18191C","nativeValues":"0.094 0.098 0.110","nativeSpaceName":"sRGB","x":1,"y":2},{"hex":1}]"##
        let recent = try JSONDecoder().decode([Lenient<PickedColor>].self, from: Data(old.utf8)).compactMap(\.value)
        #expect(recent.map(\.hex) == ["#18191C"])
    }

    // MARK: Clicks on the image

    @Test func aClickGoesToRecentNewestFirstAndKeepsEight() {
        var state = ColorMeterState()
        for n in 1...10 { state.pick(color(n)) }
        #expect(state.recent == (3...10).reversed().map(color))
    }

    @Test func withoutATargetAClickOnlyGoesToRecent() {
        var state = ColorMeterState()
        state.pick(color(1))
        state.pick(color(2))
        #expect(state.recent == [color(2), color(1)])
        #expect(state.text == nil)
        #expect(state.background == nil)
        #expect(state.favorites.allSatisfy { $0 == nil })
        #expect(state.target == nil)
    }

    @Test func aTargetedContrastSlotTakesEveryClickAndStaysTheTarget() {
        var state = ColorMeterState()
        state.clickContrast(.background)
        for n in 1...3 { state.pick(color(n)) }
        #expect(state.background == color(3))
        #expect(state.text == nil)
        #expect(state.target == .contrast(.background))
    }

    @Test func aTargetedFavouriteTakesOneClickAndStopsBeingTheTarget() {
        var state = ColorMeterState()
        state.clickFavorite(2)
        #expect(state.target == .favorite(2))
        state.pick(color(1))
        #expect(state.favorites[2] == color(1))
        #expect(state.target == nil)
        state.pick(color(2))
        #expect(state.favorites[2] == color(1))
        #expect(state.favorites.compactMap { $0 } == [color(1)])
        #expect(state.text == nil)
    }

    @Test func aClickIntoATargetedFavouriteDoesntGoToRecent() {
        var state = state(recent: 2)
        state.clickRecent(1)
        state.clickFavorite(0)
        state.pick(color(3))
        #expect(state.favorites[0] == color(3))
        #expect(state.recent == [color(2), color(1)])
        #expect(state.focus == .recent(1))
        // The next plain click goes to Recent again.
        state.pick(color(4))
        #expect(state.recent == [color(4), color(2), color(1)])
    }

    @Test func aClickIntoTextOrBackgroundStillGoesToRecent() {
        var state = ColorMeterState()
        state.clickContrast(.background)
        state.pick(color(1))
        #expect(state.background == color(1))
        #expect(state.recent == [color(1)])
    }

    @Test func aClickOnTheImageMovesARecentFocusDownWithIt() {
        var state = state(recent: 3)
        state.clickRecent(1)
        state.pick(color(4))
        #expect(state.focus == .recent(2))
        #expect(state.focused == color(2))
    }

    @Test func aFocusedRecentPushedOutReturnsFocusToLive() {
        var state = state(recent: 8)
        state.clickRecent(7)
        state.pick(color(9))
        #expect(state.focus == .live)
        #expect(state.focused == nil)
    }

    // MARK: Recent

    @Test func aRecentClickWithoutATargetOnlyFocuses() {
        var state = state(recent: 3)
        state.clickRecent(1)
        #expect(state.focus == .recent(1))
        #expect(state.focused == color(2))
        #expect(state.text == nil && state.background == nil)
        #expect(state.favorites.allSatisfy { $0 == nil })
    }

    @Test func aRecentClickFillsATargetedContrastSlotWhichStays() {
        var state = state(recent: 3)
        state.clickContrast(.text)
        state.clickRecent(2)
        #expect(state.text == color(1))
        #expect(state.target == .contrast(.text))
        #expect(state.focus == .recent(2))
    }

    @Test func aRecentClickFillsATargetedFavouriteWhichStops() {
        var state = state(recent: 3)
        state.clickFavorite(5)
        state.clickRecent(0)
        #expect(state.favorites[5] == color(3))
        #expect(state.target == nil)
        #expect(state.focus == .recent(0))
    }

    @Test func aRecentClickOutOfRangeChangesNothing() {
        var state = state(recent: 2)
        let before = state
        state.clickRecent(2)
        state.clickRecent(-1)
        #expect(state == before)
    }

    @Test func removingTheFocusedRecentReturnsFocusToLive() {
        var state = state(recent: 3)
        state.clickRecent(1)
        state.removeRecent(1)
        #expect(state.focus == .live)
        #expect(state.recent == [color(3), color(1)])
    }

    @Test func removingARecentAboveTheFocusedOneKeepsFocusOnTheSameColour() {
        var state = state(recent: 3)
        state.clickRecent(2)
        state.removeRecent(0)
        #expect(state.focus == .recent(1))
        #expect(state.focused == color(1))
        state.removeRecent(5)
        #expect(state.recent.count == 2)
    }

    @Test func removingARecentBelowTheFocusedOneKeepsTheFocus() {
        var state = state(recent: 3)
        state.clickRecent(0)
        state.removeRecent(2)
        #expect(state.focus == .recent(0))
        #expect(state.focused == color(3))
    }

    @Test func clearingRecentReturnsARecentFocusToLiveOnly() {
        var state = state(recent: 3)
        state.clickRecent(0)
        state.clearRecent()
        #expect(state.recent.isEmpty)
        #expect(state.focus == .live)

        var other = self.state(recent: 3)
        fill(.text, with: color(3), in: &other)
        other.clickContrast(.text)
        other.clearRecent()
        #expect(other.focus == .contrast(.text))
        #expect(other.text == color(3))
    }

    @Test func removingARecentLeavesTheColourWhereItWasPut() {
        var state = ColorMeterState()
        fill(.text, with: color(1), in: &state)
        #expect(state.addToFavorites(recent: 0) == true)
        state.removeRecent(0)
        #expect(state.text == color(1))
        #expect(state.favorites[0] == color(1))
    }

    // MARK: Add to Favorites

    @Test func addToFavoritesTakesTheFirstEmptySlot() {
        var state = ColorMeterState()
        state.clickFavorite(0)
        state.pick(color(1))
        state.pick(color(2))
        #expect(state.recent == [color(2)])
        #expect(state.addToFavorites(recent: 0) == true)
        #expect(state.favorites[0] == color(1))
        #expect(state.favorites[1] == color(2))
        state.removeFavorite(0)
        state.pick(color(3))
        #expect(state.addToFavorites(recent: 0) == true)
        #expect(state.favorites[0] == color(3))
    }

    @Test func addToFavoritesWhenFullChangesNothing() {
        var state = ColorMeterState()
        for n in 1...8 { favorite(color(n), in: &state) }
        state.pick(color(9))
        let before = state
        #expect(state.addToFavorites(recent: 0) == false)
        #expect(state == before)
        #expect(state.addToFavorites(recent: 20) == false)
    }

    @Test func addToFavoritesLeavesTheTargetAndFocus() {
        var state = state(recent: 2)
        state.clickFavorite(0)
        state.clickRecent(1)
        // The recent click filled the targeted favourite 0; favourite 3 is targeted next.
        state.clickFavorite(3)
        #expect(state.addToFavorites(recent: 0) == true)
        #expect(state.favorites[1] == color(2))
        #expect(state.target == .favorite(3))
        #expect(state.focus == .recent(1))
    }

    // MARK: Favourites

    @Test func aClickOnAnEmptyFavouriteTargetsItWithoutFocusing() {
        var state = state(recent: 1)
        state.clickRecent(0)
        state.clickFavorite(4)
        #expect(state.target == .favorite(4))
        #expect(state.focus == .recent(0))
        state.clickFavorite(4)
        #expect(state.target == nil)
    }

    @Test func aClickOnAFilledFavouriteTargetsAndFocusesIt() {
        var state = ColorMeterState()
        favorite(color(1), in: &state)
        state.clickFavorite(0)
        #expect(state.target == .favorite(0))
        #expect(state.focus == .favorite(0))
        #expect(state.focused == color(1))
        state.clickFavorite(0)
        #expect(state.target == nil)
        #expect(state.focus == .favorite(0))
    }

    @Test func anotherFavouriteTakesTheTargetOver() {
        var state = ColorMeterState()
        state.clickFavorite(1)
        state.clickFavorite(6)
        #expect(state.target == .favorite(6))
    }

    @Test func aFilledFavouriteFillsATargetedContrastSlot() {
        var state = ColorMeterState()
        favorite(color(1), in: &state)
        state.clickContrast(.background)
        state.clickFavorite(0)
        #expect(state.background == color(1))
        #expect(state.target == .contrast(.background))
        #expect(state.focus == .favorite(0))
    }

    @Test func anEmptyFavouriteClickedWhileTextIsTargetedBecomesTheTarget() {
        var state = ColorMeterState()
        fill(.text, with: color(1), in: &state)
        state.clickContrast(.text)
        state.clickFavorite(3)
        #expect(state.target == .favorite(3))
        #expect(state.text == color(1))
        #expect(state.focus == .contrast(.text))
    }

    @Test func removingATargetedFavouriteKeepsItTargetedToBeFilledAgain() {
        var state = ColorMeterState()
        favorite(color(1), in: &state)
        state.clickFavorite(0)
        state.removeFavorite(0)
        #expect(state.favorites[0] == nil)
        #expect(state.target == .favorite(0))
        #expect(state.focus == .live)
        state.pick(color(2))
        #expect(state.favorites[0] == color(2))
    }

    @Test func removingAnotherFavouriteKeepsTheFocus() {
        var state = ColorMeterState()
        favorite(color(1), in: &state)
        favorite(color(2), in: &state)
        state.clickFavorite(1)
        state.removeFavorite(0)
        #expect(state.focus == .favorite(1))
        state.removeFavorite(8)
        #expect(state.favorites.count == ColorMeterState.favoriteCount)
    }

    @Test func aFavouriteClickOutOfRangeChangesNothing() {
        var state = ColorMeterState()
        state.clickFavorite(8)
        state.clickFavorite(-1)
        #expect(state == ColorMeterState())
    }

    // MARK: Contrast slots

    @Test func aContrastSlotClickTogglesTheTargetAndFocusesAFilledSlot() {
        var state = ColorMeterState()
        state.clickContrast(.text)
        #expect(state.target == .contrast(.text))
        #expect(state.focus == .live)
        state.pick(color(1))
        #expect(state.text == color(1))
        state.clickContrast(.text)
        #expect(state.target == nil)
        #expect(state.focus == .contrast(.text))
        state.clickContrast(.text)
        state.clickContrast(.background)
        #expect(state.target == .contrast(.background))
    }

    @Test func aContrastSlotClickTakesTheTargetFromAFavourite() {
        var state = ColorMeterState()
        state.clickFavorite(2)
        state.clickContrast(.background)
        #expect(state.target == .contrast(.background))
    }

    @Test func swapExchangesTheColoursKeepsTheTargetOnItsSlotAndTheFocusOnItsColour() {
        var state = ColorMeterState()
        fill(.text, with: color(1), in: &state)
        fill(.background, with: color(2), in: &state)
        state.clickContrast(.text)
        state.swap()
        #expect(state.text == color(2))
        #expect(state.background == color(1))
        #expect(state.target == .contrast(.text))
        #expect(state.focus == .contrast(.background))
        #expect(state.focused == color(1))
    }

    @Test func swapWithOneSlotEmptyMovesTheColourAndItsFocus() {
        var state = ColorMeterState()
        fill(.text, with: color(1), in: &state)
        state.clickContrast(.text)
        state.swap()
        #expect(state.text == nil)
        #expect(state.background == color(1))
        #expect(state.focused == color(1))
    }

    @Test func swapLeavesAnotherFocus() {
        var state = state(recent: 2)
        state.clickRecent(1)
        state.swap()
        #expect(state.focus == .recent(1))
    }

    // MARK: Target and focus

    @Test func clearTargetSaysWhetherThereWasOne() {
        var state = ColorMeterState()
        #expect(state.clearTarget() == false)
        state.clickContrast(.background)
        #expect(state.clearTarget() == true)
        #expect(state.target == nil)
        state.clickFavorite(0)
        #expect(state.clearTarget() == true)
        #expect(state.target == nil)
    }

    @Test func movingOverTheImageBringsTheLivePixelBackAndKeepsTheTarget() {
        var state = ColorMeterState()
        fill(.text, with: color(1), in: &state)
        state.clickContrast(.text)
        #expect(state.pointerMovedOverImage() == true)
        #expect(state.focus == .live)
        #expect(state.target == .contrast(.text))
        #expect(state.pointerMovedOverImage() == false)
    }

    @Test func movingOverTheImageReturnsFocusFromEveryKeptColour() {
        var state = state(recent: 1)
        favorite(color(2), in: &state)
        for click in [{ (s: inout ColorMeterState) in s.clickRecent(0) }, { $0.clickFavorite(0) }] {
            click(&state)
            #expect(state.focus != .live)
            #expect(state.pointerMovedOverImage() == true)
            #expect(state.focused == nil)
        }
    }

    @Test func theFocusedColourFollowsItsElement() {
        var state = ColorMeterState()
        fill(.text, with: color(1), in: &state)
        state.clickContrast(.text)
        state.pick(color(2))
        #expect(state.focused == color(2))
    }

    @Test func theHintSaysWhereColoursGo() {
        var state = ColorMeterState()
        #expect(state.hint == "Click Text or Background, then click colours for it.")
        state.pick(color(1))
        #expect(state.hint == "Click Text or Background, then click colours for it.")
        state.clickContrast(.text)
        #expect(state.hint == "Clicks, recent and favourite colours fill Text. Click it again to stop.")
        state.clickContrast(.background)
        #expect(state.hint == "Clicks, recent and favourite colours fill Background. Click it again to stop.")
        state.clickFavorite(2)
        #expect(state.hint == "The next click or recent colour goes into favourite 3.")
    }

    // MARK: Kept between launches

    @Test func savedColoursRoundTrip() throws {
        var state = ColorMeterState()
        favorite(color(1), in: &state)
        state.clickFavorite(5)
        state.pick(color(2))
        fill(.text, with: color(3), in: &state)
        state.clickContrast(.background)
        let data = try JSONEncoder().encode(state.saved)
        let decoded = try JSONDecoder().decode(SavedMeterColors.self, from: data)
        #expect(decoded == state.saved)
        let restored = ColorMeterState(recent: state.recent, saved: decoded)
        #expect(restored.favorites == state.favorites)
        #expect(restored.text == state.text)
        #expect(restored.background == state.background)
        #expect(restored.text == color(3))
        // The target and the focus start afresh.
        #expect(restored.target == nil)
        #expect(restored.focus == .live)
    }

    @Test func anOlderVersionsLongerRecentListKeepsTheNewest() {
        let restored = ColorMeterState(recent: (1...10).map(color))
        #expect(restored.recent == (1...8).map(color))
    }

    private func decode(_ json: String) throws -> SavedMeterColors {
        try JSONDecoder().decode(SavedMeterColors.self, from: Data(json.utf8))
    }

    private let red = ##"{"hex":"#FF0000","nativeValues":"1 0 0","nativeSpaceName":"sRGB","x":1,"y":2}"##

    @Test func nothingSavedIsEightEmptyFavouritesAndNoPair() throws {
        let saved = try decode("{}")
        #expect(saved == SavedMeterColors())
        #expect(saved.favorites.count == 8)
        #expect(saved.favorites.allSatisfy { $0 == nil })
    }

    @Test func anUnreadableFavouriteEmptiesThatSlotAlone() throws {
        let saved = try decode(#"{"favorites":[\#(red),{"hex":3},null,"x",\#(red)],"text":\#(red)}"#)
        #expect(saved.favorites.count == 8)
        #expect(saved.favorites[0]?.hex == "#FF0000")
        #expect(saved.favorites[1] == nil)
        #expect(saved.favorites[2] == nil)
        #expect(saved.favorites[3] == nil)
        #expect(saved.favorites[4]?.hex == "#FF0000")
        #expect(saved.text?.x == 1)
        #expect(saved.background == nil)
    }

    @Test func extraFavouritesAreDroppedAndMissingOnesEmpty() throws {
        let ten = Array(repeating: red, count: 10).joined(separator: ",")
        #expect(try decode(#"{"favorites":[\#(ten)]}"#).favorites.count == 8)
        #expect(try decode(#"{"favorites":[\#(red)]}"#).favorites.compactMap { $0 }.count == 1)
    }

    @Test func anUnreadableKeyCostsThatValueAlone() throws {
        let saved = try decode(#"{"favorites":"none","text":{"hex":1},"background":\#(red)}"#)
        #expect(saved.favorites == SavedMeterColors().favorites)
        #expect(saved.text == nil)
        #expect(saved.background?.hex == "#FF0000")
    }
}
