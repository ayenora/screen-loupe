import CoreGraphics
import Foundation
import Testing

/// A 1000 × 600 window fitted by the area; y up, so the top margin is taken off `maxY`.
private let frame = CGRect(x: 100, y: 200, width: 1000, height: 600)
private let minimum = CaptureAreaEditing.minimumSize

struct CaptureMarginsTests {
    @Test func noMarginsLeaveTheWholeFrame() {
        #expect(CaptureMargins().inner(of: frame) == frame)
    }

    @Test func theInnerRectIsTheFrameLessEachMargin() {
        let margins = CaptureMargins(left: 10, top: 80, right: 30, bottom: 20)
        // Left and bottom move the origin; top comes off the top edge, which is maxY.
        #expect(margins.inner(of: frame) == CGRect(x: 110, y: 220, width: 960, height: 500))
    }

    @Test func theInnerRectWorksAtNegativeCoordinates() {
        let left = CGRect(x: -1920, y: -300, width: 800, height: 400)
        let margins = CaptureMargins(left: 12, top: 40, right: 8, bottom: 4)
        #expect(margins.inner(of: left) == CGRect(x: -1908, y: -296, width: 780, height: 356))
    }

    @Test func marginsThatFitApplyAsStored() {
        let margins = CaptureMargins(left: 100, top: 50, right: 200, bottom: 60)
        #expect(margins.applied(to: frame.size) == margins)
    }

    @Test func theRightMarginGivesWayFirstThenTheLeft() {
        // 300 wide leaves 236 for both: the right gives its 64.
        let margins = CaptureMargins(left: 100, top: 0, right: 200, bottom: 0)
        let size = CGSize(width: 300, height: 600)
        #expect(margins.applied(to: size) == CaptureMargins(left: 100, top: 0, right: 136, bottom: 0))
        // 150 wide leaves 86: the right gives all it has, then the left the rest.
        let narrow = margins.applied(to: CGSize(width: 150, height: 600))
        #expect(narrow == CaptureMargins(left: 86, top: 0, right: 0, bottom: 0))
        #expect(margins.inner(of: CGRect(x: 0, y: 0, width: 150, height: 600)).width == minimum.width)
    }

    @Test func theBottomMarginGivesWayFirstThenTheTop() {
        let margins = CaptureMargins(left: 0, top: 40, right: 0, bottom: 30)
        #expect(
            margins.applied(to: CGSize(width: 500, height: 124))
                == CaptureMargins(left: 0, top: 40, right: 0, bottom: 20))
        #expect(
            margins.applied(to: CGSize(width: 500, height: 90)) == CaptureMargins(left: 0, top: 26, right: 0, bottom: 0)
        )
    }

    @Test func aFrameAtTheMinimumLeavesNoMargins() {
        let margins = CaptureMargins(left: 10, top: 10, right: 10, bottom: 10)
        #expect(margins.applied(to: minimum) == CaptureMargins())
        #expect(margins.inner(of: CGRect(origin: .zero, size: minimum)) == CGRect(origin: .zero, size: minimum))
    }

    @Test func theStoredMarginsComeBackAsTheWindowGrowsAgain() {
        // Set on the full window, as the panel sets them.
        let margins = CaptureMargins()
            .setting(.left, to: 100, frameSize: frame.size)
            .setting(.top, to: 50, frameSize: frame.size)
            .setting(.right, to: 200, frameSize: frame.size)
            .setting(.bottom, to: 60, frameSize: frame.size)
        #expect(margins == CaptureMargins(left: 100, top: 50, right: 200, bottom: 60))
        // The window shrinks: they give way, and the inner rect keeps the minimum.
        let small = CGRect(x: 100, y: 200, width: 300, height: 150)
        #expect(margins.applied(to: small.size) == CaptureMargins(left: 100, top: 50, right: 136, bottom: 36))
        #expect(margins.inner(of: small).size == minimum)
        // Back to its size: what was stored applies again.
        #expect(margins.applied(to: frame.size) == margins)
        #expect(margins.inner(of: frame) == CGRect(x: 200, y: 260, width: 700, height: 490))
    }

    @Test func negativeStoredMarginsApplyAsNone() {
        let margins = CaptureMargins(left: -10, top: -1, right: 5, bottom: 0)
        #expect(margins.applied(to: frame.size) == CaptureMargins(left: 0, top: 0, right: 5, bottom: 0))
    }

    // MARK: Setting a margin

    @Test(arguments: [
        (CGFloat(12.4), CGFloat(12)),
        (CGFloat(12.5), CGFloat(13)),
        (CGFloat(-3), CGFloat(0)),
    ])
    func aMarginIsSetInWholePointsNeverBelowZero(value: CGFloat, expected: CGFloat) {
        #expect(CaptureMargins().setting(.top, to: value, frameSize: frame.size).top == expected)
    }

    @Test func aMarginLeavesTheInnerRectAtLeastTheMinimumBesideTheOpposite() {
        let margins = CaptureMargins(left: 100, top: 0, right: 0, bottom: 200)
        // 1000 − 64 − 100 for the right; 600 − 64 − 200 for the top.
        #expect(margins.setting(.right, to: 5000, frameSize: frame.size).right == 836)
        #expect(margins.setting(.top, to: 5000, frameSize: frame.size).top == 336)
    }

    @Test func aMarginIsClampedBesideTheOppositeAsItApplies() {
        // Stored 400 + 500 in a 700-wide frame: the right applies as 236.
        let margins = CaptureMargins(left: 400, top: 0, right: 500, bottom: 0)
        let size = CGSize(width: 700, height: 600)
        let next = margins.setting(.left, to: 1000, frameSize: size)
        #expect(next.left == 400)
        // The other margins stay as stored.
        #expect(next.right == 500)
    }

    @Test func aMarginBesideAnOppositeThatLeavesOnlyTheMinimumIsZero() {
        // 164 wide with 100 on the left: 64 left for the inner rect, nothing for the right.
        let margins = CaptureMargins(left: 100, top: 0, right: 0, bottom: 0)
        let size = CGSize(width: 164, height: 300)
        #expect(margins.setting(.right, to: 20, frameSize: size).right == 0)
        // Narrower still: the left gives way, and the right still gets nothing.
        let narrower = CGSize(width: 120, height: 300)
        #expect(margins.setting(.right, to: 20, frameSize: narrower).right == 0)
        #expect(margins.setting(.left, to: 80, frameSize: narrower).left == 56)
    }

    @Test func aFrameAtOrBelowTheMinimumTakesNoMargin() {
        for size in [minimum, CGSize(width: 50, height: 40)] {
            for edge in CaptureMargins.Edge.allCases {
                #expect(CaptureMargins().setting(edge, to: 10, frameSize: size)[edge] == 0)
            }
        }
    }

    @Test func aFractionalFrameRoomRoundsDown() {
        let size = CGSize(width: 164.5, height: 300)
        #expect(CaptureMargins().setting(.left, to: 500, frameSize: size).left == 100)
    }

    // MARK: Units

    @Test(arguments: [
        (SizeUnits.pixels, CGFloat(2), CGFloat(2)),
        (.pixels, 1, 1),
        (.points, 2, 1),
        (.pointsAndPixels, 2, 1),
    ])
    func thePanelShowsPixelsOnlyWhenTheTabDoes(units: SizeUnits, scale: CGFloat, factor: CGFloat) {
        #expect(CaptureMargins.shownPerPoint(units: units, scale: scale) == factor)
    }

    @Test func typedPixelsOnARetinaDisplayBecomeWholePoints() {
        // 25 px is 12.5 pt: 13 pt, shown as 26 px.
        let points = CaptureMargins.points(fromShown: 25, factor: 2)
        #expect(points == 13)
        #expect(CaptureMargins.shown(points, factor: 2) == 26)
        #expect(SizeText.number(CaptureMargins.shown(points, factor: 2)) == "26")
        #expect(CaptureMargins.points(fromShown: 24, factor: 2) == 12)
    }

    @Test func typedPixelsOnA1xDisplayAreThePoints() {
        #expect(CaptureMargins.points(fromShown: 25, factor: 1) == 25)
        #expect(CaptureMargins.points(fromShown: 25.4, factor: 1) == 25)
        #expect(CaptureMargins.shown(25, factor: 1) == 25)
    }

    // MARK: Scrubbing

    @Test(arguments: [
        (false, false, 25.0),
        (true, false, 160.0),
        (false, true, 11.5),
    ])
    func aCaptionScrubsOneStepPerPointShiftTimesTenOptionATenth(shift: Bool, option: Bool, expected: Double) {
        #expect(Scrub.value(from: 10, travel: 15, step: 1, shift: shift, option: option) == expected)
    }

    @Test func scrubbingLeftLowersTheValue() {
        #expect(Scrub.value(from: 10, travel: -4, step: 1, shift: false, option: false) == 6)
    }
}
