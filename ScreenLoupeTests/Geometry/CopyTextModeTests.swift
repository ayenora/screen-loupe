import Testing

struct CopyTextModeTests {
    private func on(over picture: CopyTextMode.Picture) -> CopyTextMode {
        var mode = CopyTextMode()
        _ = mode.turnOn(over: picture, canFreeze: true, selectIsOn: false)
        return mode
    }

    // MARK: Turning on and off

    @Test func itStartsOff() {
        let mode = CopyTextMode()
        #expect(!mode.isOn)
        #expect(!mode.frozeLive)
    }

    @Test func overTheLiveViewItFreezesItThenReadsIt() {
        var mode = CopyTextMode()
        #expect(mode.turnOn(over: .live, canFreeze: true, selectIsOn: false) == [.freeze, .showText])
        #expect(mode.isOn)
        #expect(mode.frozeLive)
    }

    @Test func overAStillPictureItReadsItAsItIs() {
        var mode = CopyTextMode()
        #expect(mode.turnOn(over: .still, canFreeze: true, selectIsOn: false) == [.showText])
        #expect(mode.isOn)
        #expect(!mode.frozeLive)
    }

    @Test func withNothingToFreezeItStaysOff() {
        var mode = CopyTextMode()
        #expect(mode.turnOn(over: .live, canFreeze: false, selectIsOn: true) == [.beep])
        #expect(!mode.isOn)
        #expect(!mode.frozeLive)
    }

    @Test func aStillPictureNeedsNoFreezeToBeAllowed() {
        var mode = CopyTextMode()
        #expect(mode.turnOn(over: .still, canFreeze: false, selectIsOn: false) == [.showText])
        #expect(mode.isOn)
    }

    @Test func turningOnTwiceDoesNothingMore() {
        var mode = on(over: .live)
        #expect(mode.turnOn(over: .still, canFreeze: true, selectIsOn: true) == [])
        #expect(mode.frozeLive)
    }

    @Test func leavingUnfreezesItsOwnFreeze() {
        var mode = on(over: .live)
        #expect(mode.turnOff() == [.hideText, .unfreeze])
        #expect(!mode.isOn)
        #expect(!mode.frozeLive)
    }

    @Test func leavingKeepsAFreezeItDidntMake() {
        var mode = on(over: .still)
        #expect(mode.turnOff() == [.hideText])
        #expect(!mode.isOn)
    }

    @Test func turningOffWhileOffDoesNothing() {
        var mode = CopyTextMode()
        #expect(mode.turnOff() == [])
    }

    @Test func toggleTurnsOnThenOff() {
        var mode = CopyTextMode()
        #expect(mode.toggle(over: .live, canFreeze: true, selectIsOn: false) == [.freeze, .showText])
        #expect(mode.toggle(over: .still, canFreeze: true, selectIsOn: false) == [.hideText, .unfreeze])
        #expect(mode == CopyTextMode())
    }

    @Test func afterLeavingTheNextTurnOnStartsAfresh() {
        var mode = on(over: .live)
        _ = mode.turnOff()
        #expect(mode.turnOn(over: .still, canFreeze: true, selectIsOn: false) == [.showText])
        #expect(!mode.frozeLive)
    }

    // MARK: Select

    @Test func turningOnTurnsSelectOffFirst() {
        var mode = CopyTextMode()
        #expect(mode.turnOn(over: .live, canFreeze: true, selectIsOn: true) == [.turnOffSelect, .freeze, .showText])
        var still = CopyTextMode()
        #expect(still.turnOn(over: .still, canFreeze: true, selectIsOn: true) == [.turnOffSelect, .showText])
    }

    @Test func selectComingOnEndsTheModeAndKeepsItsFreeze() {
        var mode = on(over: .live)
        #expect(mode.selectTurnedOn() == [.hideText])
        #expect(!mode.isOn)
        #expect(!mode.frozeLive)
        var still = on(over: .still)
        #expect(still.selectTurnedOn() == [.hideText])
    }

    @Test func theFreezeHandedToSelectIsNoLongerTheModes() {
        var mode = on(over: .live)
        _ = mode.selectTurnedOn()
        // Turned on again over the frame it froze, now an ordinary freeze: leaving keeps it.
        #expect(mode.turnOn(over: .still, canFreeze: true, selectIsOn: true) == [.turnOffSelect, .showText])
        #expect(mode.turnOff() == [.hideText])
        #expect(mode.space(showsFrozenLive: true) == nil)
    }

    @Test func selectComingOnWithTheModeOffChangesNothing() {
        var mode = CopyTextMode()
        #expect(mode.selectTurnedOn() == [])
        #expect(mode == CopyTextMode())
    }

    // MARK: The picture changing

    @Test func anotherStillPictureIsReadAgain() {
        var mode = on(over: .live)
        #expect(mode.pictureChanged(to: .still) == [.showText])
        #expect(mode.isOn)
        // Who froze is kept, so leaving from a recent capture resumes the live view under it.
        #expect(mode.frozeLive)
        #expect(mode.turnOff() == [.hideText, .unfreeze])
    }

    @Test func goingLiveEndsTheModeWithNothingToUnfreeze() {
        var mode = on(over: .live)
        #expect(mode.pictureChanged(to: .live) == [.hideText])
        #expect(mode == CopyTextMode())
        var still = on(over: .still)
        #expect(still.pictureChanged(to: .live) == [.hideText])
        #expect(!still.isOn)
    }

    @Test func picturesChangingWhileOffAskNothing() {
        var mode = CopyTextMode()
        #expect(mode.pictureChanged(to: .still) == [])
        #expect(mode.pictureChanged(to: .live) == [])
        #expect(mode == CopyTextMode())
    }

    // MARK: Space

    @Test func spaceIsntTheModesWhileOff() {
        var mode = CopyTextMode()
        #expect(mode.space(showsFrozenLive: true) == nil)
    }

    @Test func spaceLeavesAndResumesItsOwnFreeze() {
        var mode = on(over: .live)
        #expect(mode.space(showsFrozenLive: true) == [.hideText, .unfreeze])
        #expect(mode == CopyTextMode())
    }

    @Test func spaceAlsoResumesAFreezeMadeBefore() {
        var mode = on(over: .still)
        #expect(mode.space(showsFrozenLive: true) == [.hideText, .unfreeze])
        #expect(!mode.isOn)
    }

    @Test func spaceOverARecentCaptureOnlyLeaves() {
        var mode = on(over: .still)
        #expect(mode.space(showsFrozenLive: false) == [.hideText])
    }

    @Test func spaceOverARecentCaptureResumesTheModesFreezeUnderIt() {
        var mode = on(over: .live)
        _ = mode.pictureChanged(to: .still)
        #expect(mode.space(showsFrozenLive: false) == [.hideText, .unfreeze])
    }

    // MARK: Escape

    @Test func escapeIsntTheModesWhileOff() {
        var mode = CopyTextMode()
        #expect(mode.escape(hasTextSelection: true) == nil)
        #expect(mode.escape(hasTextSelection: false) == nil)
    }

    @Test func escapeDropsTheTextSelectionFirst() {
        var mode = on(over: .live)
        #expect(mode.escape(hasTextSelection: true) == [.clearTextSelection])
        #expect(mode.isOn)
        #expect(mode.frozeLive)
    }

    @Test func thenEscapeLeavesThenItIsNoLongerTheModes() {
        var mode = on(over: .live)
        #expect(mode.escape(hasTextSelection: true) == [.clearTextSelection])
        #expect(mode.escape(hasTextSelection: false) == [.hideText, .unfreeze])
        #expect(mode.escape(hasTextSelection: false) == nil)
    }

    @Test func escapeOverAStillPictureLeavesItStill() {
        var mode = on(over: .still)
        #expect(mode.escape(hasTextSelection: false) == [.hideText])
        #expect(mode.escape(hasTextSelection: false) == nil)
    }
}
