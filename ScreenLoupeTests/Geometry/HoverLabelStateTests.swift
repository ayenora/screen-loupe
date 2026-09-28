import Foundation
import Testing

struct HoverLabelStateTests {
    private typealias State = HoverLabelState<String>
    private let rest = HoverLabelDelay.rest

    // MARK: Enter

    @Test func theFirstEnterWaitsTheRest() {
        var state = State()
        #expect(state.enter("copy", at: 10, labelShown: false) == .wait(rest))
        #expect(state.hovered == "copy")
        #expect(state.hiddenAt == nil)
    }

    @Test func fromAShownNameToTheNextButtonShowsAtOnce() {
        var state = State()
        _ = state.enter("copy", at: 10, labelShown: false)
        // The name showed; the pointer goes on to the next button, entering it before leaving this one.
        #expect(state.enter("save", at: 11, labelShown: true) == .show)
        #expect(state.hovered == "save")
        #expect(state.hiddenAt == 11)
    }

    @Test func fromAButtonWhoseNameHadNotShownYetWaitsTheRest() {
        var state = State()
        _ = state.enter("copy", at: 10, labelShown: false)
        #expect(state.enter("save", at: 10.2, labelShown: false) == .wait(rest))
        #expect(state.hiddenAt == nil)
    }

    // MARK: Exit

    @Test func anExitAfterANameShowedLetsTheNextShowAtOnceWithinTheGrace() {
        var state = State()
        _ = state.enter("copy", at: 10, labelShown: false)
        #expect(state.exit("copy", at: 12, labelShown: true) == true)
        #expect(state.hovered == nil)
        #expect(state.hiddenAt == 12)
        #expect(state.enter("save", at: 12 + HoverLabelDelay.grace, labelShown: false) == .show)
    }

    @Test func pastTheGraceTheNextWaitsTheRest() {
        var state = State()
        _ = state.enter("copy", at: 10, labelShown: false)
        _ = state.exit("copy", at: 12, labelShown: true)
        #expect(state.enter("save", at: 12.6, labelShown: false) == .wait(rest))
    }

    @Test func anExitBeforeTheNameShowedLeavesNoGrace() {
        var state = State()
        _ = state.enter("copy", at: 10, labelShown: false)
        #expect(state.exit("copy", at: 10.3, labelShown: false) == true)
        #expect(state.hiddenAt == nil)
        #expect(state.enter("save", at: 10.4, labelShown: false) == .wait(rest))
    }

    @Test func aStaleExitChangesNothing() {
        var state = State()
        _ = state.enter("copy", at: 10, labelShown: false)
        _ = state.enter("save", at: 11, labelShown: true)
        // The exit from the button left first comes after the next one's enter.
        #expect(state.exit("copy", at: 11, labelShown: true) == false)
        #expect(state.hovered == "save")
        #expect(state.hiddenAt == 11)
    }

    @Test func anExitWithNothingHoveredChangesNothing() {
        var state = State()
        #expect(state.exit("copy", at: 10, labelShown: false) == false)
        #expect(state.hiddenAt == nil)
    }

    @Test func aSecondExitFromTheSameButtonChangesNothing() {
        var state = State()
        _ = state.enter("copy", at: 10, labelShown: false)
        _ = state.exit("copy", at: 12, labelShown: true)
        #expect(state.exit("copy", at: 13, labelShown: false) == false)
        #expect(state.hiddenAt == 12)
    }

    // MARK: End

    @Test func aClickEndsItAndTheNextWaitsTheRest() {
        var state = State()
        _ = state.enter("copy", at: 10, labelShown: false)
        state.end()
        #expect(state.hovered == nil)
        #expect(state.hiddenAt == nil)
        #expect(state.enter("save", at: 11, labelShown: false) == .wait(rest))
    }

    @Test func hidingForgetsARecentlyShownName() {
        var state = State()
        _ = state.enter("copy", at: 10, labelShown: false)
        _ = state.exit("copy", at: 12, labelShown: true)
        state.end()
        #expect(state.enter("save", at: 12.1, labelShown: false) == .wait(rest))
    }

    @Test func anExitAfterAClickIsStale() {
        var state = State()
        _ = state.enter("copy", at: 10, labelShown: false)
        state.end()
        #expect(state.exit("copy", at: 11, labelShown: false) == false)
    }

    @Test func reenteringTheSameButtonAfterAClickWaitsTheRest() {
        var state = State()
        _ = state.enter("copy", at: 10, labelShown: false)
        state.end()
        #expect(state.enter("copy", at: 10.1, labelShown: false) == .wait(rest))
        #expect(state.hovered == "copy")
    }
}
