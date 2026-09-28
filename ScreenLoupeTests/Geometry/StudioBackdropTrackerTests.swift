import CoreGraphics
import Testing

private let primary = DisplayInfo(id: 1, globalFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2)
private let left = DisplayInfo(id: 2, globalFrame: CGRect(x: -1920, y: -300, width: 1920, height: 1080), scale: 1)
/// The primary display at another scale: the same place, more pixels.
private let primaryAt3 = DisplayInfo(id: 1, globalFrame: primary.globalFrame, scale: 3)

private let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
private let p3 = CGColorSpace(name: CGColorSpace.displayP3)!

private let white = StudioBackground.color(.white)
private let black = StudioBackground.color(.black)

private func target(
    _ background: StudioBackground = white, on display: DisplayInfo = primary, space: CGColorSpace = srgb
) -> StudioBackdrop.Target {
    StudioBackdrop.Target(
        placement: StudioBackdrop.Placement(
            display: display, background: background, pixelSize: StudioBackdrop.pixelSize(of: display)),
        space: space)
}

/// A tracker showing `shown`, its drawing finished.
private func showing(_ shown: StudioBackdrop.Target) -> StudioBackdrop.Tracker {
    var tracker = StudioBackdrop.Tracker()
    _ = tracker.update(wanted: shown)
    _ = tracker.finished(tracker.request, drawn: true)
    return tracker
}

struct StudioBackdropTrackerTests {
    // MARK: Nothing wanted

    @Test func hiddenStudioOrTheScreenWithNothingShownDoesNothing() {
        var tracker = StudioBackdrop.Tracker()
        #expect(tracker.update(wanted: nil) == .none)
        #expect(tracker.shown == nil)
        #expect(tracker.asked == nil)
    }

    @Test func nothingWantedHidesAShownBackdropAtOnce() {
        var tracker = showing(target())
        #expect(tracker.update(wanted: nil) == .hide)
        #expect(tracker.shown == nil)
        #expect(tracker.asked == nil)
    }

    @Test func nothingWantedDropsAPendingDrawing() {
        var tracker = StudioBackdrop.Tracker()
        guard case .render(_, let request, _) = tracker.update(wanted: target()) else {
            Issue.record("Expected a drawing")
            return
        }
        #expect(tracker.update(wanted: nil) == .none)
        #expect(tracker.finished(request, drawn: true) == .stale)
        #expect(tracker.shown == nil)
    }

    // MARK: Drawing

    @Test func theFirstBackgroundIsDrawnWithoutHiding() {
        var tracker = StudioBackdrop.Tracker()
        #expect(tracker.update(wanted: target()) == .render(target(), request: 1, hidesFirst: false))
        #expect(tracker.asked == target())
        #expect(tracker.shown == nil)
    }

    @Test func aFinishedDrawingShowsAndAnnouncesTheWindow() {
        var tracker = StudioBackdrop.Tracker()
        _ = tracker.update(wanted: target())
        #expect(tracker.finished(1, drawn: true) == .shown(announces: true))
        #expect(tracker.shown == target())
    }

    @Test func theSameBackgroundOnTheSameDisplayDoesNoWork() {
        var tracker = showing(target())
        #expect(tracker.update(wanted: target()) == .none)
        #expect(tracker.shown == target())
        // Moving the frame within its display, again and again.
        let request = tracker.request
        #expect(tracker.update(wanted: target()) == .none)
        #expect(tracker.update(wanted: target()) == .none)
        #expect(tracker.request == request)
    }

    @Test func theSameWantedWhileItIsDrawnIsNotAskedAgain() {
        var tracker = StudioBackdrop.Tracker()
        _ = tracker.update(wanted: target())
        #expect(tracker.update(wanted: target()) == .none)
        #expect(tracker.request == 1)
        #expect(tracker.finished(1, drawn: true) == .shown(announces: true))
    }

    @Test func anotherBackgroundKeepsTheOldPictureUntilDrawn() {
        var tracker = showing(target(white))
        #expect(tracker.update(wanted: target(black)) == .render(target(black), request: 2, hidesFirst: false))
        #expect(tracker.shown == target(white))
        // Replacing a shown picture announces nothing: the window was already there.
        #expect(tracker.finished(2, drawn: true) == .shown(announces: false))
        #expect(tracker.shown == target(black))
    }

    // MARK: Display, scale, colour space

    @Test func anotherDisplayHidesTheOldPictureAtOnce() {
        var tracker = showing(target(on: primary))
        #expect(tracker.update(wanted: target(on: left)) == .render(target(on: left), request: 2, hidesFirst: true))
        #expect(tracker.shown == nil)
        #expect(tracker.finished(2, drawn: true) == .shown(announces: true))
    }

    @Test func anotherScaleRedrawsWithoutHiding() {
        var tracker = showing(target(on: primary))
        #expect(
            tracker.update(wanted: target(on: primaryAt3))
                == .render(target(on: primaryAt3), request: 2, hidesFirst: false))
        #expect(tracker.shown == target(on: primary))
    }

    @Test func anotherColourSpaceRedrawsWithoutHiding() {
        var tracker = showing(target(space: srgb))
        #expect(tracker.update(wanted: target(space: p3)) == .render(target(space: p3), request: 2, hidesFirst: false))
        #expect(tracker.finished(2, drawn: true) == .shown(announces: false))
        #expect(tracker.shown == target(space: p3))
    }

    @Test func colourSpacesMadeApartButAlikeAreTheSame() {
        var tracker = showing(target(space: srgb))
        #expect(tracker.update(wanted: target(space: CGColorSpace(name: CGColorSpace.sRGB)!)) == .none)
    }

    // MARK: Stale drawings

    @Test func backToWhatShowsWhileAnotherIsDrawnDropsTheDrawing() {
        // A → B → A: B's picture, finishing late, must not replace A.
        var tracker = showing(target(white))
        _ = tracker.update(wanted: target(black))
        #expect(tracker.update(wanted: target(white)) == .none)
        #expect(tracker.asked == nil)
        #expect(tracker.finished(2, drawn: true) == .stale)
        #expect(tracker.shown == target(white))
    }

    @Test func aNewerRequestDropsTheOlderResult() {
        var tracker = showing(target(white))
        _ = tracker.update(wanted: target(black))
        let gradient = StudioBackground.gradient(StudioBackground.gradients[0].gradient)
        #expect(tracker.update(wanted: target(gradient)) == .render(target(gradient), request: 3, hidesFirst: false))
        #expect(tracker.finished(2, drawn: true) == .stale)
        #expect(tracker.shown == target(white))
        #expect(tracker.finished(3, drawn: true) == .shown(announces: false))
        #expect(tracker.shown == target(gradient))
    }

    @Test func aStaleFailureIsDroppedToo() {
        var tracker = showing(target(white))
        _ = tracker.update(wanted: target(black))
        _ = tracker.update(wanted: target(white))
        #expect(tracker.finished(2, drawn: false) == .stale)
        #expect(tracker.shown == target(white))
    }

    // MARK: Failures

    @Test func aFailureHidesAShownBackdrop() {
        var tracker = showing(target(white))
        _ = tracker.update(wanted: target(black))
        #expect(tracker.finished(2, drawn: false) == .failed(hides: true))
        #expect(tracker.shown == nil)
    }

    @Test func aFailureWithNothingShownHidesNothing() {
        var tracker = StudioBackdrop.Tracker()
        _ = tracker.update(wanted: target())
        #expect(tracker.finished(1, drawn: false) == .failed(hides: false))
    }

    @Test func aFailureIsNotTriedAgainOnEveryMove() {
        var tracker = StudioBackdrop.Tracker()
        _ = tracker.update(wanted: target())
        _ = tracker.finished(1, drawn: false)
        #expect(tracker.update(wanted: target()) == .none)
        // Another background is tried.
        #expect(tracker.update(wanted: target(black)) == .render(target(black), request: 2, hidesFirst: false))
    }

    @Test func aFailureIsTriedAgainAfterTheBackdropWasHidden() {
        var tracker = StudioBackdrop.Tracker()
        _ = tracker.update(wanted: target())
        _ = tracker.finished(1, drawn: false)
        _ = tracker.update(wanted: nil)
        #expect(tracker.update(wanted: target()) == .render(target(), request: 3, hidesFirst: false))
    }

    @Test func aResultAfterTheStudioHidAndShowedAgainIsStale() {
        var tracker = StudioBackdrop.Tracker()
        _ = tracker.update(wanted: target())
        _ = tracker.update(wanted: nil)
        #expect(tracker.update(wanted: target()) == .render(target(), request: 3, hidesFirst: false))
        #expect(tracker.finished(1, drawn: true) == .stale)
        #expect(tracker.finished(3, drawn: true) == .shown(announces: true))
    }
}
