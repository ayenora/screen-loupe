import CoreGraphics
import Foundation
import Testing

private let converter: DisplayCoordinateConverter = {
    let primary = DisplayInfo(id: 1, globalFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2)
    let left = DisplayInfo(id: 2, globalFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1080), scale: 1)
    guard let layout = DisplayLayout(displays: [primary, left]) else { fatalError("Fixture has a primary display") }
    return DisplayCoordinateConverter(layout: layout)
}()

private func geometry(_ rect: CGRect) -> CaptureGeometry? {
    converter.captureGeometry(for: GlobalRect(rect: rect))
}

/// The area before and after the magnet moved it one point right: the same size, another place.
private let before = CGRect(x: 100, y: 100, width: 120, height: 80)
private let after = CGRect(x: 101, y: 100, width: 120, height: 80)

struct MagnetHoldTests {
    private func check(_ hold: MagnetHold, at time: TimeInterval, showsArea: Bool) -> Bool {
        hold.ends(on: .check(at: time, showsArea: showsArea))
    }

    @Test func itHoldsWhileTheWindowMoves() {
        var hold = MagnetHold(movedTo: before, at: 10)
        // A move every 1/60 s: never still for long enough, even with a frame of the area.
        for step in 1...30 {
            let time = 10 + Double(step) / 60
            hold.moved(to: after, at: time)
            #expect(!check(hold, at: time + 1.0 / 120, showsArea: true))
        }
    }

    @Test func itEndsOnceStillWithAFrameOfTheArea() {
        let hold = MagnetHold(movedTo: after, at: 10)
        #expect(!check(hold, at: 10.149, showsArea: true))
        #expect(check(hold, at: 10 + MagnetHold.settle, showsArea: true))
        #expect(check(hold, at: 10.5, showsArea: true))
    }

    @Test func aStaleFrameKeepsItHoldingAfterTheWindowStopsHoweverLong() {
        let hold = MagnetHold(movedTo: after, at: 10)
        #expect(!check(hold, at: 10.2, showsArea: false))
        #expect(!check(hold, at: 11, showsArea: false))
        // Nothing on screen changed for a minute: still held, never a stale frame.
        #expect(!check(hold, at: 70, showsArea: false))
    }

    @Test func aMoveStartsTheStillTimeAgain() {
        var hold = MagnetHold(movedTo: before, at: 10)
        hold.moved(to: after, at: 10.14)
        #expect(!check(hold, at: 10.2, showsArea: true))
        #expect(!check(hold, at: 10.28, showsArea: true))
        #expect(check(hold, at: 10.3, showsArea: true))
        #expect(hold.lastMove == 10.14)
        #expect(hold.area == after)
    }

    @Test func theSettleCheckIsDueWhenTheWindowHasBeenStillLongEnough() {
        let hold = MagnetHold(movedTo: after, at: 10)
        #expect(abs((hold.untilSettled(at: 10) ?? 0) - MagnetHold.settle) < 1e-9)
        #expect(abs((hold.untilSettled(at: 10.05) ?? 0) - 0.1) < 1e-9)
        #expect(hold.untilSettled(at: 10 + MagnetHold.settle) == nil)
        #expect(hold.untilSettled(at: 12) == nil)
    }

    @Test func aUserMoveOrResizeEndsItButTheMagnetsOwnPlaceDoesNot() {
        let hold = MagnetHold(movedTo: after, at: 10)
        // The tab's text changed, or a notice showed: the area is where the magnet put it.
        #expect(!hold.ends(on: .areaChanged(to: after)))
        // A handle dragged, or Fit to Window.
        #expect(hold.ends(on: .areaChanged(to: CGRect(x: 101, y: 100, width: 140, height: 80))))
        #expect(hold.ends(on: .areaChanged(to: CGRect(x: 300, y: 300, width: 120, height: 80))))
    }

    @Test(arguments: [
        MagnetHold.Event.frozen, .recentCaptureShown, .viewerClosed, .magnetStopped, .displaysChanged,
        .captureInterrupted,
    ])
    func whatTakesTheLiveViewsPlaceEndsItAtOnce(_ event: MagnetHold.Event) {
        // Mid-move, without a frame of the area.
        let hold = MagnetHold(movedTo: after, at: 10)
        #expect(hold.ends(on: event))
    }

    @Test func theOutlineFollowsTheAreaOnlyOnTheHeldFramesDisplay() throws {
        let now = try #require(geometry(after))
        let old = try #require(geometry(before))
        #expect(MagnetHold.viewedPartGeometry(area: now, held: old) == now)
        // Carried onto the 1× display left of the 2× one: the held pixels are of another size.
        let onLeft = try #require(geometry(CGRect(x: -500, y: 100, width: 120, height: 80)))
        #expect(MagnetHold.viewedPartGeometry(area: onLeft, held: old) == nil)
        #expect(MagnetHold.viewedPartGeometry(area: nil, held: old) == nil)
        #expect(MagnetHold.viewedPartGeometry(area: now, held: nil) == nil)
    }

    @Test func aFrameShowsTheAreaOnlyWithItsGeometryCapturedAfterTheStreamTookItOn() throws {
        let now = try #require(geometry(after))
        let old = try #require(geometry(before))
        #expect(now != old)
        #expect(MagnetHold.frameShows(now, frameGeometry: now, capturedAfterConfiguring: true))
        // Labelled with the new geometry but captured before the stream took it on.
        #expect(!MagnetHold.frameShows(now, frameGeometry: now, capturedAfterConfiguring: false))
        // Of the area before its last move.
        #expect(!MagnetHold.frameShows(now, frameGeometry: old, capturedAfterConfiguring: true))
        #expect(!MagnetHold.frameShows(now, frameGeometry: nil, capturedAfterConfiguring: true))
        // The area on no display.
        #expect(!MagnetHold.frameShows(nil, frameGeometry: now, capturedAfterConfiguring: true))
    }

    @Test func aFrameOnAnotherDisplayDoesntShowTheArea() throws {
        let onLeft = CGRect(x: -500, y: 100, width: 120, height: 80)
        let now = try #require(geometry(onLeft))
        let old = try #require(geometry(before))
        #expect(!MagnetHold.frameShows(now, frameGeometry: old, capturedAfterConfiguring: true))
    }

    @Test func aFrameCountsOnlyWhenCapturedAfterTheStreamTookTheGeometryOn() {
        #expect(MagnetHold.isCaptured(at: 1_000, afterConfiguringAt: 999))
        #expect(MagnetHold.isCaptured(at: 1_000, afterConfiguringAt: 1_000))
        #expect(!MagnetHold.isCaptured(at: 998, afterConfiguringAt: 999))
        // Not taken on yet, or a frame without a capture time.
        #expect(!MagnetHold.isCaptured(at: 1_000, afterConfiguringAt: nil))
        #expect(!MagnetHold.isCaptured(at: nil, afterConfiguringAt: 0))
        // A new stream: every frame of it has its geometry.
        #expect(MagnetHold.isCaptured(at: 0, afterConfiguringAt: 0))
    }

    /// The window resized with a fitted area: the stream takes another source rect and another size.
    private let resized = CGRect(x: 100, y: 100, width: 160, height: 80)

    @Test func aResizeByTheMagnetKeepsItHoldingAndDoesntEndIt() {
        var hold = MagnetHold(movedTo: before, at: 10)
        hold.moved(to: resized, at: 10.1)
        // The area where the magnet put it: not the user's change.
        #expect(!hold.ends(on: .areaChanged(to: resized)))
        #expect(!check(hold, at: 10.2, showsArea: true))
        #expect(check(hold, at: 10.1 + MagnetHold.settle, showsArea: true))
    }

    @Test func aFrameOfTheSizeBeforeAResizeDoesntShowTheArea() throws {
        let now = try #require(geometry(resized))
        let old = try #require(geometry(before))
        // The same top-left corner, another size: other pixels out of the stream.
        #expect(now.outputSize != old.outputSize)
        #expect(!MagnetHold.frameShows(now, frameGeometry: old, capturedAfterConfiguring: true))
        #expect(MagnetHold.frameShows(now, frameGeometry: now, capturedAfterConfiguring: true))
        // A 2× area 1 pt taller: one more row of two pixels is enough.
        let taller = try #require(geometry(CGRect(x: 100, y: 100, width: 120, height: 81)))
        #expect(!MagnetHold.frameShows(taller, frameGeometry: old, capturedAfterConfiguring: true))
    }
}
