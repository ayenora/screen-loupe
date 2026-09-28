import CoreGraphics
import Testing

struct SnapshotFrameTests {
    @Test func theLiveViewTakesTheLatestFrame() {
        #expect(RecentCaptureRules.snapshotFrame(frozen: nil, held: nil, live: "live") == "live")
    }

    @Test func aFrozenViewTakesTheFrozenFrame() {
        #expect(RecentCaptureRules.snapshotFrame(frozen: "frozen", held: nil, live: "live") == "frozen")
    }

    /// While the magnet moves the area the live view shows the held frame; the latest may not show
    /// the area yet.
    @Test func aHoldTakesTheHeldFrame() {
        #expect(RecentCaptureRules.snapshotFrame(frozen: nil, held: "held", live: "live") == "held")
    }

    @Test func frozenComesBeforeHeld() {
        #expect(RecentCaptureRules.snapshotFrame(frozen: "frozen", held: "held", live: "live") == "frozen")
    }

    @Test func aFrozenFrameIsTakenAlsoWithoutALiveOne() {
        #expect(RecentCaptureRules.snapshotFrame(frozen: "frozen", held: nil, live: nil) == "frozen")
    }

    @Test func noFrameTakesNothing() {
        #expect(RecentCaptureRules.snapshotFrame(frozen: String?.none, held: nil, live: nil) == nil)
    }
}

struct SnapshotViewTests {
    @Test func onTheLiveViewTheCurrentZoomAndPan() {
        #expect(RecentCaptureRules.snapshotView(savedLive: nil, current: "current") == "current")
    }

    /// With a row shown, the current zoom and pan are the row's.
    @Test func withARowShownTheLiveViewsPutAway() {
        #expect(RecentCaptureRules.snapshotView(savedLive: "live", current: "row") == "live")
    }
}

struct RecentCaptureListTests {
    private func adding(_ item: Int, to items: [Int], shown: Int? = nil) -> [Int] {
        RecentCaptureRules.adding(item, to: items) { $0 == shown }
    }

    @Test func theLimitIsEight() {
        #expect(RecentCaptureRules.limit == 8)
    }

    @Test func theFirstGoesOnItsOwn() {
        #expect(adding(1, to: []) == [1])
    }

    @Test func theNewestGoesOnTop() {
        #expect(adding(3, to: [2, 1]) == [3, 2, 1])
    }

    @Test func belowTheLimitNothingGoes() {
        #expect(adding(8, to: [7, 6, 5, 4, 3, 2, 1]) == [8, 7, 6, 5, 4, 3, 2, 1])
    }

    @Test func theNinthDropsTheOldest() {
        #expect(adding(9, to: [8, 7, 6, 5, 4, 3, 2, 1]) == [9, 8, 7, 6, 5, 4, 3, 2])
    }

    @Test func theShownOldestStaysAndTheNextOldestGoes() {
        #expect(adding(9, to: [8, 7, 6, 5, 4, 3, 2, 1], shown: 1) == [9, 8, 7, 6, 5, 4, 3, 1])
    }

    @Test func aShownRowInTheMiddleLeavesTheOldestToGo() {
        #expect(adding(9, to: [8, 7, 6, 5, 4, 3, 2, 1], shown: 5) == [9, 8, 7, 6, 5, 4, 3, 2])
    }

    @Test func theNewestShownStillDropsTheOldest() {
        #expect(adding(9, to: [8, 7, 6, 5, 4, 3, 2, 1], shown: 9) == [9, 8, 7, 6, 5, 4, 3, 2])
    }
}

struct RecentCaptureSizeTextTests {
    @Test func theSizeIsInPixels() {
        #expect(RecentCaptureRules.sizeText(PixelSize(width: 294, height: 239)) == "294 × 239 px")
    }

    /// As every size in the app: no thousands separators.
    @Test func largeSizesHaveNoSeparators() {
        #expect(RecentCaptureRules.sizeText(PixelSize(width: 4957, height: 3384)) == "4957 × 3384 px")
    }

    @Test func aSinglePixel() {
        #expect(RecentCaptureRules.sizeText(PixelSize(width: 1, height: 1)) == "1 × 1 px")
    }
}
