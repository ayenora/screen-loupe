import CoreGraphics
import Foundation
import Testing

/// Decodes `delay` as the settings do: `value(_:or:)` with off as the fallback.
private struct Saved: Decodable {
    let delay: StudioDelay

    private enum CodingKeys: String, CodingKey { case delay }

    init(from decoder: Decoder) throws {
        delay = try decoder.container(keyedBy: CodingKeys.self).value(.delay, or: StudioDelay.off)
    }
}

private func decoded(_ json: String) throws -> StudioDelay {
    try JSONDecoder().decode(Saved.self, from: Data(json.utf8)).delay
}

struct StudioDelayTests {
    @Test func theDelaysAreOffAndThreeFiveAndTenSeconds() {
        #expect(StudioDelay.allCases == [.off, .three, .five, .ten])
        #expect(StudioDelay.allCases.map(\.title) == ["Off", "3 s", "5 s", "10 s"])
    }

    @Test func aDelayIsSavedAsItsSeconds() throws {
        for delay in StudioDelay.allCases {
            let data = try JSONEncoder().encode(["delay": delay])
            #expect(String(decoding: data, as: UTF8.self) == "{\"delay\":\(delay.rawValue)}")
            #expect(try decoded("{\"delay\": \(delay.rawValue)}") == delay)
        }
    }

    @Test func aMissingOrUnknownDelayIsOff() throws {
        #expect(try decoded("{}") == .off)
        #expect(try decoded("{\"delay\": 7}") == .off)
        #expect(try decoded("{\"delay\": -3}") == .off)
        #expect(try decoded("{\"delay\": \"5\"}") == .off)
        #expect(try decoded("{\"delay\": 5.5}") == .off)
        #expect(try decoded("{\"delay\": null}") == .off)
    }
}

/// A press that can be taken, with no picker running, unless said otherwise.
private func press(
    _ shot: StudioShot, delay: StudioDelay, check: StudioShotCheck = .take, pickerRunning: Bool = false,
    at now: TimeInterval
) -> StudioCountdown.Event {
    .press(shot, delay: delay, check: check, pickerRunning: pickerRunning, at: now)
}

/// A tick with the frame on a display, unless said otherwise.
private func tick(at now: TimeInterval, frameOnDisplay: Bool = true) -> StudioCountdown.Event {
    .tick(at: now, frameOnDisplay: frameOnDisplay)
}

struct StudioCountdownTests {
    @Test func withoutADelayAPressShootsAtOnce() {
        for shot in [StudioShot.capture, .copy, .save] {
            let (next, outcome) = StudioCountdown.idle.after(press(shot, delay: .off, at: 100))
            #expect(next == .idle)
            #expect(outcome == .shootNow(shot))
        }
    }

    @Test func withADelayAPressStartsTheCountdown() {
        for delay in [StudioDelay.three, .five, .ten] {
            let (next, outcome) = StudioCountdown.idle.after(press(.save, delay: delay, at: 100))
            #expect(next == .counting(.save, start: 100, total: TimeInterval(delay.rawValue)))
            #expect(outcome == .started(stopsPicker: false))
        }
    }

    @Test func withADelayAPressThatWouldBeRefusedIsRefusedAtOnce() {
        for check in [StudioShotCheck.ignore, .bringSavePanelForward, .needsPermission, .notOnOneDisplay] {
            let (next, outcome) = StudioCountdown.idle.after(press(.copy, delay: .five, check: check, at: 100))
            #expect(next == .idle)
            #expect(outcome == .refusedNow(.copy))
        }
    }

    @Test func withoutADelayThePressShootsAndTheShotChecksItself() {
        let (next, outcome) = StudioCountdown.idle.after(press(.save, delay: .off, check: .notOnOneDisplay, at: 100))
        #expect(next == .idle)
        #expect(outcome == .shootNow(.save))
    }

    @Test func aPressDuringACountdownCancelsWithoutACheck() {
        let counting = StudioCountdown.counting(.copy, start: 100, total: 5)
        for check in [StudioShotCheck.take, .ignore, .bringSavePanelForward, .needsPermission, .notOnOneDisplay] {
            #expect(counting.after(press(.copy, delay: .five, check: check, at: 101)) == (.idle, .cancelled))
            #expect(
                counting.after(press(.save, delay: .five, check: check, pickerRunning: true, at: 101))
                    == (.idle, .cancelled))
        }
    }

    @Test func aCountdownStartedWhileAPickerRunsStopsThePickerFirst() {
        let (next, outcome) = StudioCountdown.idle.after(press(.copy, delay: .three, pickerRunning: true, at: 100))
        #expect(next == .counting(.copy, start: 100, total: 3))
        #expect(outcome == .started(stopsPicker: true))
        // Without a delay the shot is taken at once, as without a timer: the picker is left alone.
        #expect(
            StudioCountdown.idle.after(press(.copy, delay: .off, pickerRunning: true, at: 100))
                == (.idle, .shootNow(.copy)))
    }

    @Test func aFrameOnNoDisplayStopsTheCountdown() {
        let counting = StudioCountdown.counting(.copy, start: 100, total: 5)
        #expect(counting.after(tick(at: 101, frameOnDisplay: false)) == (.idle, .frameOffDisplay))
        // Also at zero: nothing is fired for a frame on no display.
        #expect(counting.after(tick(at: 105, frameOnDisplay: false)) == (.idle, .frameOffDisplay))
        #expect(StudioCountdown.idle.after(tick(at: 101, frameOnDisplay: false)) == (.idle, .none))
        let (next, _) = counting.after(tick(at: 101, frameOnDisplay: false))
        #expect(next.after(tick(at: 106)) == (.idle, .none))
    }

    @Test func ticksBeforeZeroChangeNothing() {
        let counting = StudioCountdown.counting(.copy, start: 100, total: 3)
        for now in [100, 101, 102.5, 102.999] {
            let (next, outcome) = counting.after(tick(at: now))
            #expect(next == counting)
            #expect(outcome == .none)
        }
    }

    @Test func atZeroItFiresTheShotItWasStartedFor() {
        for shot in [StudioShot.capture, .copy, .save] {
            let counting = StudioCountdown.counting(shot, start: 100, total: 5)
            #expect(counting.after(tick(at: 105)) == (.idle, .fire(shot)))
            // A late tick, the Mac having slept or the main thread held up, fires too.
            #expect(counting.after(tick(at: 160)) == (.idle, .fire(shot)))
        }
    }

    @Test func itFiresOnce() {
        let (next, _) = StudioCountdown.counting(.copy, start: 100, total: 3).after(tick(at: 103))
        #expect(next.after(tick(at: 103.1)) == (.idle, .none))
    }

    @Test func theSameButtonAgainCancels() {
        let counting = StudioCountdown.counting(.copy, start: 100, total: 5)
        #expect(counting.after(press(.copy, delay: .five, at: 102)) == (.idle, .cancelled))
    }

    @Test func anotherButtonCancelsAndStartsNothing() {
        let counting = StudioCountdown.counting(.copy, start: 100, total: 5)
        #expect(counting.after(press(.save, delay: .five, at: 102)) == (.idle, .cancelled))
        #expect(counting.after(press(.capture, delay: .ten, at: 102)) == (.idle, .cancelled))
        // Also with the delay turned off meanwhile: nothing is taken at once.
        #expect(counting.after(press(.save, delay: .off, at: 102)) == (.idle, .cancelled))
    }

    @Test func hidingTheStudioCancels() {
        let counting = StudioCountdown.counting(.capture, start: 100, total: 10)
        #expect(counting.after(.hidden) == (.idle, .cancelled))
        #expect(StudioCountdown.idle.after(.hidden) == (.idle, .none))
    }

    @Test func startingAWindowPickerCancels() {
        let counting = StudioCountdown.counting(.copy, start: 100, total: 5)
        #expect(counting.after(.pickerStarted) == (.idle, .cancelled))
        #expect(StudioCountdown.idle.after(.pickerStarted) == (.idle, .none))
        let (next, _) = counting.after(.pickerStarted)
        #expect(next.after(tick(at: 106)) == (.idle, .none))
    }

    @Test func oneWindowsWindowLostCancelsAndNothingFires() {
        let counting = StudioCountdown.counting(.capture, start: 100, total: 5)
        #expect(counting.after(.windowLost) == (.idle, .cancelled))
        #expect(StudioCountdown.idle.after(.windowLost) == (.idle, .none))
        let (next, _) = counting.after(.windowLost)
        #expect(next.after(tick(at: 106)) == (.idle, .none))
    }

    @Test func aCancelledCountdownNeverFires() {
        let (next, _) = StudioCountdown.counting(.save, start: 100, total: 3).after(.hidden)
        #expect(next.after(tick(at: 104)) == (.idle, .none))
    }

    @Test func ticksWhileIdleDoNothing() {
        #expect(StudioCountdown.idle.after(tick(at: 100)) == (.idle, .none))
    }

    @Test func aDelayChangedDuringTheCountdownAppliesToTheNextPress() {
        // The countdown knows only the delay it started with.
        let (counting, _) = StudioCountdown.idle.after(press(.copy, delay: .ten, at: 100))
        #expect(counting.after(tick(at: 103)) == (counting, .none))
        #expect(counting.after(tick(at: 110)) == (.idle, .fire(.copy)))
        let (again, _) = StudioCountdown.idle.after(press(.copy, delay: .three, at: 200))
        #expect(again.after(tick(at: 203)) == (.idle, .fire(.copy)))
    }

    @Test func aNewCountdownCanStartAfterOneEnds() {
        let (idle, _) = StudioCountdown.counting(.copy, start: 100, total: 3).after(.hidden)
        #expect(
            idle.after(press(.save, delay: .five, at: 110)) == (
                .counting(.save, start: 110, total: 5), .started(stopsPicker: false)
            ))
    }

    @Test func theSecondsLeftCountDownFromTheDelay() {
        let counting = StudioCountdown.counting(.copy, start: 100, total: 3)
        #expect(counting.secondsLeft(at: 100) == 3)
        #expect(counting.secondsLeft(at: 100.01) == 3)
        #expect(counting.secondsLeft(at: 101) == 2)
        #expect(counting.secondsLeft(at: 101.5) == 2)
        #expect(counting.secondsLeft(at: 102.99) == 1)
        #expect(counting.secondsLeft(at: 103) == 0)
        #expect(counting.secondsLeft(at: 110) == 0)
        #expect(StudioCountdown.idle.secondsLeft(at: 100) == 0)
    }

    @Test func theRingEmptiesFromFullToNothing() {
        let counting = StudioCountdown.counting(.copy, start: 100, total: 4)
        #expect(counting.fractionLeft(at: 100) == 1)
        #expect(counting.fractionLeft(at: 99) == 1)
        #expect(counting.fractionLeft(at: 101) == 0.75)
        #expect(counting.fractionLeft(at: 102) == 0.5)
        #expect(counting.fractionLeft(at: 104) == 0)
        #expect(counting.fractionLeft(at: 120) == 0)
        #expect(StudioCountdown.idle.fractionLeft(at: 100) == 0)
    }

    @Test func theTextNamesTheShotAndTheSeconds() {
        #expect(
            StudioCountdown.counting(.copy, start: 100, total: 3).text(at: 100) == "Copying in 3 s")
        #expect(
            StudioCountdown.counting(.save, start: 100, total: 10).text(at: 101) == "Saving in 9 s")
        #expect(
            StudioCountdown.counting(.capture, start: 100, total: 5).text(at: 104.5)
                == "Capturing in 1 s")
        #expect(StudioCountdown.idle.text(at: 100) == "")
    }
}

struct StudioCountdownPlacementTests {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let size = CGSize(width: 180, height: 28)

    @Test func itSitsLeftOfTheTabCentredOnItsRow() {
        let tab = CGRect(x: 600, y: 700, width: 200, height: 22)
        #expect(
            StudioCountdown.pillRect(size: size, tab: tab, screen: screen)
                == CGRect(x: 416, y: 697, width: 180, height: 28))
    }

    @Test func withoutRoomOnTheLeftItGoesRightOfTheTab() {
        let tab = CGRect(x: 100, y: 700, width: 200, height: 22)
        #expect(
            StudioCountdown.pillRect(size: size, tab: tab, screen: screen)
                == CGRect(x: 304, y: 697, width: 180, height: 28))
    }

    @Test func itStaysOnTheDisplay() {
        // Too wide for either side: kept inside the right edge.
        let tab = CGRect(x: 20, y: 700, width: 1300, height: 22)
        let pill = StudioCountdown.pillRect(size: size, tab: tab, screen: screen)
        #expect(pill.maxX == CGFloat(1434))
        // A tab at the display's top: the pill doesn't go above it.
        let top = StudioCountdown.pillRect(
            size: size, tab: CGRect(x: 600, y: 872, width: 200, height: 22), screen: screen)
        #expect(top.maxY == CGFloat(894))
        let bottom = StudioCountdown.pillRect(
            size: size, tab: CGRect(x: 600, y: 4, width: 200, height: 22), screen: screen)
        #expect(bottom.minY == CGFloat(6))
    }

    @Test func itWorksOnADisplayLeftOfAndBelowTheMainOne() {
        let screen = CGRect(x: -1920, y: -1080, width: 1920, height: 1080)
        let tab = CGRect(x: -1000, y: -300, width: 200, height: 22)
        #expect(
            StudioCountdown.pillRect(size: size, tab: tab, screen: screen)
                == CGRect(x: -1184, y: -303, width: 180, height: 28))
        let atLeftEdge = CGRect(x: -1900, y: -300, width: 200, height: 22)
        #expect(StudioCountdown.pillRect(size: size, tab: atLeftEdge, screen: screen).minX == CGFloat(-1696))
    }

    @Test func itLandsOnWholePoints() {
        let tab = CGRect(x: 600.4, y: 700.3, width: 200, height: 21)
        let pill = StudioCountdown.pillRect(size: CGSize(width: 180.5, height: 28), tab: tab, screen: screen)
        #expect(pill.minX == pill.minX.rounded())
        #expect(pill.minY == pill.minY.rounded())
    }
}

struct StudioShotCheckTests {
    private func check(
        visible: Bool = true, capturing: Bool = false, savePanelOpen: Bool = false, permitted: Bool = true,
        onOneDisplay: Bool = true
    ) -> StudioShotCheck {
        StudioShotCheck(
            visible: visible, capturing: capturing, savePanelOpen: savePanelOpen, permitted: permitted,
            onOneDisplay: onOneDisplay)
    }

    @Test func aShownStudioOnOneDisplayTakesThePicture() {
        #expect(check() == .take)
    }

    @Test func aHiddenStudioOrAPictureOnItsWayIgnoresThePress() {
        #expect(check(visible: false) == .ignore)
        #expect(check(capturing: true) == .ignore)
        #expect(check(visible: false, savePanelOpen: true, permitted: false, onOneDisplay: false) == .ignore)
    }

    @Test func anOpenSavePanelComesForwardBeforeAnythingElseIsChecked() {
        #expect(check(savePanelOpen: true) == .bringSavePanelForward)
        #expect(check(savePanelOpen: true, permitted: false, onOneDisplay: false) == .bringSavePanelForward)
    }

    @Test func withoutPermissionTheViewerExplains() {
        #expect(check(permitted: false) == .needsPermission)
        #expect(check(permitted: false, onOneDisplay: false) == .needsPermission)
    }

    @Test func aFrameAcrossDisplaysIsRefused() {
        #expect(check(onOneDisplay: false) == .notOnOneDisplay)
    }

    @Test func aCountdownThatFiresIsCheckedOnWhatHoldsThen() {
        // Started while the frame was on one display; moved across two before zero.
        #expect(check() == .take)
        let (_, outcome) = StudioCountdown.counting(.copy, start: 0, total: 3).after(tick(at: 3))
        #expect(outcome == .fire(.copy))
        #expect(check(onOneDisplay: false) == .notOnOneDisplay)
        // Hidden meanwhile: the hide cancelled it, and a fire that came anyway is ignored.
        #expect(check(visible: false) == .ignore)
    }
}
