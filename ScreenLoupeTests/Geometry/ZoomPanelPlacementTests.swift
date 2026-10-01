import CoreGraphics
import Foundation
import Testing

struct ZoomPanelPlacementTests {
    private let panel = CGSize(width: 64, height: 330)
    private let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)

    // MARK: Default

    @Test func defaultIsRightOfTheViewerTopAligned() {
        let viewer = CGRect(x: 200, y: 200, width: 800, height: 600)
        let offset = ZoomPanelPlacement.defaultOffset(size: panel, viewer: viewer, visibleFrames: [visible])
        #expect(offset == ZoomPanelOffset(edge: .right, dx: 8, dy: 0))
        let frame = ZoomPanelPlacement.frame(size: panel, offset: offset, viewer: viewer)
        #expect(frame == CGRect(x: 1008, y: 800 - 330, width: 64, height: 330))
    }

    @Test func defaultFitsRightExactlyAtTheScreenEdge() {
        // 1440 - 8 - 64 = 1368: the panel's right side is on the visible frame's.
        let viewer = CGRect(x: 568, y: 200, width: 800, height: 600)
        let offset = ZoomPanelPlacement.defaultOffset(size: panel, viewer: viewer, visibleFrames: [visible])
        #expect(offset.edge == .right)
    }

    @Test func defaultGoesLeftWhenTheRightHasNoRoom() {
        let viewer = CGRect(x: 569, y: 200, width: 800, height: 600)
        let offset = ZoomPanelPlacement.defaultOffset(size: panel, viewer: viewer, visibleFrames: [visible])
        #expect(offset == ZoomPanelOffset(edge: .left, dx: -8 - 64, dy: 0))
        let frame = ZoomPanelPlacement.frame(size: panel, offset: offset, viewer: viewer)
        #expect(frame.maxX == CGFloat(569 - 8))
        #expect(frame.maxY == viewer.maxY)
    }

    @Test func defaultStaysRightWhenNeitherSideHasRoom() {
        let viewer = CGRect(x: 20, y: 0, width: 1400, height: 875)
        let offset = ZoomPanelPlacement.defaultOffset(size: panel, viewer: viewer, visibleFrames: [visible])
        #expect(offset.edge == .right)
        // Kept on screen: over the Viewer, inside the right edge.
        let origin = ZoomPanelPlacement.origin(
            size: panel, offset: offset, viewer: viewer, visibleFrames: [visible], fallback: visible)
        #expect(origin == CGPoint(x: 1440 - 64, y: 875 - 330))
    }

    @Test func defaultOnADisplayLeftOfThePrimary() {
        let left = CGRect(x: -1920, y: 0, width: 1920, height: 1055)
        let viewer = CGRect(x: -900, y: 100, width: 880, height: 700)
        let offset = ZoomPanelPlacement.defaultOffset(size: panel, viewer: viewer, visibleFrames: [visible, left])
        #expect(offset.edge == .left)
        let origin = ZoomPanelPlacement.origin(
            size: panel, offset: offset, viewer: viewer, visibleFrames: [visible, left], fallback: left)
        #expect(origin == CGPoint(x: -900 - 8 - 64, y: 800 - 330))
    }

    @Test func defaultFitsLeftExactlyAtTheScreenEdge() {
        // Right: 1400 + 8 + 64 > 1440. Left: 72 - 8 - 64 = 0, on the visible frame's left side.
        let viewer = CGRect(x: 72, y: 200, width: 1328, height: 600)
        let offset = ZoomPanelPlacement.defaultOffset(size: panel, viewer: viewer, visibleFrames: [visible])
        #expect(offset == ZoomPanelOffset(edge: .left, dx: -72, dy: 0))
        // A point further left: no room there either, so the right.
        let wider = CGRect(x: 71, y: 200, width: 1329, height: 600)
        #expect(ZoomPanelPlacement.defaultOffset(size: panel, viewer: wider, visibleFrames: [visible]).edge == .right)
    }

    @Test func defaultForAViewerPartlyOffTheScreensRightEdge() {
        // The right side would be on no display.
        let viewer = CGRect(x: 1200, y: 200, width: 800, height: 600)
        let offset = ZoomPanelPlacement.defaultOffset(size: panel, viewer: viewer, visibleFrames: [visible])
        #expect(offset.edge == .left)
        let origin = ZoomPanelPlacement.origin(
            size: panel, offset: offset, viewer: viewer, visibleFrames: [visible], fallback: visible)
        #expect(origin == CGPoint(x: 1200 - 8 - 64, y: 800 - 330))
    }

    @Test func defaultForAViewerPartlyAboveTheScreen() {
        // Its top is past the visible frame's: the side still fits across, and the panel is kept
        // under the top.
        let viewer = CGRect(x: 200, y: 500, width: 800, height: 600)
        let offset = ZoomPanelPlacement.defaultOffset(size: panel, viewer: viewer, visibleFrames: [visible])
        #expect(offset.edge == .right)
        let origin = ZoomPanelPlacement.origin(
            size: panel, offset: offset, viewer: viewer, visibleFrames: [visible], fallback: visible)
        #expect(origin == CGPoint(x: 1008, y: 875 - 330))
    }

    @Test func defaultOnTheNextDisplayWhenTheViewerIsAtItsDisplaysEdge() {
        let second = CGRect(x: 1440, y: 0, width: 1920, height: 1055)
        let viewer = CGRect(x: 640, y: 200, width: 800, height: 600)
        // On the primary alone the right has no room; with the display beside it, it has.
        #expect(ZoomPanelPlacement.defaultOffset(size: panel, viewer: viewer, visibleFrames: [visible]).edge == .left)
        let offset = ZoomPanelPlacement.defaultOffset(size: panel, viewer: viewer, visibleFrames: [visible, second])
        #expect(offset.edge == .right)
    }

    @Test func defaultWithNoDisplaysIsTheRight() {
        let viewer = CGRect(x: 200, y: 200, width: 800, height: 600)
        #expect(ZoomPanelPlacement.defaultOffset(size: panel, viewer: viewer, visibleFrames: []).edge == .right)
    }

    // MARK: Offset

    @Test func offsetFromTheNearerEdgeRoundTrips() {
        let viewer = CGRect(x: 300, y: 100, width: 800, height: 600)
        for frame in [
            CGRect(x: 1120, y: 400, width: 64, height: 330),  // right of it
            CGRect(x: 200, y: 50, width: 64, height: 330),  // left of it, lower
            CGRect(x: 700, y: -300, width: 64, height: 330),  // below it, right half
            CGRect(x: 400, y: 710, width: 64, height: 330),  // above it, left half
        ] {
            let offset = ZoomPanelPlacement.offset(of: frame, from: viewer)
            #expect(ZoomPanelPlacement.frame(size: frame.size, offset: offset, viewer: viewer) == frame)
        }
    }

    @Test func offsetEdgeIsTheOneNearerThePanelsMiddle() {
        let viewer = CGRect(x: 0, y: 0, width: 800, height: 600)
        let right = ZoomPanelPlacement.offset(of: CGRect(x: 380, y: 0, width: 64, height: 100), from: viewer)
        #expect(right == ZoomPanelOffset(edge: .right, dx: 380 - 800, dy: 100 - 600))
        let left = ZoomPanelPlacement.offset(of: CGRect(x: 300, y: 0, width: 64, height: 100), from: viewer)
        #expect(left == ZoomPanelOffset(edge: .left, dx: 300, dy: 100 - 600))
        // Level middles: the right edge.
        let level = ZoomPanelPlacement.offset(of: CGRect(x: 368, y: 0, width: 64, height: 100), from: viewer)
        #expect(level.edge == .right)
    }

    @Test func movingTheViewerTakesThePanelAlong() {
        let viewer = CGRect(x: 300, y: 100, width: 800, height: 600)
        let placed = CGRect(x: 1150, y: 300, width: 64, height: 330)
        let offset = ZoomPanelPlacement.offset(of: placed, from: viewer)
        let moved = ZoomPanelPlacement.frame(
            size: placed.size, offset: offset, viewer: viewer.offsetBy(dx: -120, dy: 45))
        #expect(moved == placed.offsetBy(dx: -120, dy: 45))
    }

    @Test func resizingTheViewerKeepsThePanelBesideItsEdge() {
        let viewer = CGRect(x: 300, y: 100, width: 800, height: 600)
        let rightPanel = CGRect(x: 1108, y: 370, width: 64, height: 330)
        let leftPanel = CGRect(x: 228, y: 370, width: 64, height: 330)
        let rightOffset = ZoomPanelPlacement.offset(of: rightPanel, from: viewer)
        let leftOffset = ZoomPanelPlacement.offset(of: leftPanel, from: viewer)
        // Wider to the right and taller at the bottom: the top and the left edge stay.
        let wider = CGRect(x: 300, y: 0, width: 1000, height: 700)
        #expect(ZoomPanelPlacement.frame(size: panel, offset: rightOffset, viewer: wider).minX == CGFloat(1308))
        #expect(ZoomPanelPlacement.frame(size: panel, offset: rightOffset, viewer: wider).maxY == CGFloat(700))
        #expect(ZoomPanelPlacement.frame(size: panel, offset: leftOffset, viewer: wider) == leftPanel)
        // Wider to the left: the right edge stays.
        let widerLeft = CGRect(x: 100, y: 100, width: 1000, height: 600)
        #expect(ZoomPanelPlacement.frame(size: panel, offset: rightOffset, viewer: widerLeft) == rightPanel)
        #expect(ZoomPanelPlacement.frame(size: panel, offset: leftOffset, viewer: widerLeft).minX == CGFloat(28))
    }

    @Test func offsetSurvivesEncoding() throws {
        let offset = ZoomPanelOffset(edge: .left, dx: -72.5, dy: -40)
        let data = try JSONEncoder().encode(offset)
        #expect(try JSONDecoder().decode(ZoomPanelOffset.self, from: data) == offset)
    }

    // MARK: Keeping on screen

    @Test func aFrameOnScreenStays() {
        let rect = CGRect(x: 100, y: 100, width: 64, height: 330)
        #expect(ZoomPanelPlacement.keptOnScreen(rect, visibleFrames: [visible], fallback: visible) == rect.origin)
    }

    @Test func aFramePastAnEdgeMovesJustInside() {
        let right = CGRect(x: 1400, y: 100, width: 64, height: 330)
        #expect(ZoomPanelPlacement.keptOnScreen(right, visibleFrames: [visible], fallback: visible).x == CGFloat(1376))
        let left = CGRect(x: -30, y: 100, width: 64, height: 330)
        #expect(ZoomPanelPlacement.keptOnScreen(left, visibleFrames: [visible], fallback: visible).x == CGFloat(0))
        let top = CGRect(x: 100, y: 700, width: 64, height: 330)
        #expect(ZoomPanelPlacement.keptOnScreen(top, visibleFrames: [visible], fallback: visible).y == CGFloat(545))
        let bottom = CGRect(x: 100, y: -100, width: 64, height: 330)
        #expect(ZoomPanelPlacement.keptOnScreen(bottom, visibleFrames: [visible], fallback: visible).y == CGFloat(0))
    }

    @Test func aFrameBiggerThanTheScreenKeepsItsTopLeftInside() {
        let small = CGRect(x: 0, y: 0, width: 50, height: 200)
        let rect = CGRect(x: -20, y: -40, width: 64, height: 330)
        let origin = ZoomPanelPlacement.keptOnScreen(rect, visibleFrames: [small], fallback: small)
        #expect(origin == CGPoint(x: 0, y: 200 - 330))
    }

    @Test func aFrameAcrossTwoDisplaysGoesToTheOneItOverlapsMost() {
        let second = CGRect(x: 1440, y: 0, width: 1920, height: 1055)
        // 24 pt on the primary, 40 on the second.
        let rect = CGRect(x: 1416, y: 100, width: 64, height: 330)
        let origin = ZoomPanelPlacement.keptOnScreen(rect, visibleFrames: [visible, second], fallback: visible)
        #expect(origin == CGPoint(x: 1440, y: 100))
        // 40 on the primary, 24 on the second.
        let mostlyPrimary = CGRect(x: 1400, y: 100, width: 64, height: 330)
        let back = ZoomPanelPlacement.keptOnScreen(mostlyPrimary, visibleFrames: [visible, second], fallback: visible)
        #expect(back == CGPoint(x: 1376, y: 100))
    }

    @Test func aFrameOnNoDisplayGoesToTheFallback() {
        let second = CGRect(x: 1440, y: 0, width: 1920, height: 1055)
        let rect = CGRect(x: 5000, y: 3000, width: 64, height: 330)
        let origin = ZoomPanelPlacement.keptOnScreen(rect, visibleFrames: [visible, second], fallback: second)
        #expect(origin == CGPoint(x: 3360 - 64, y: 1055 - 330))
        #expect(ZoomPanelPlacement.keptOnScreen(rect, visibleFrames: [], fallback: visible).x == CGFloat(1376))
    }

    @Test func aDisplayBelowThePrimaryWithNegativeCoordinates() {
        let below = CGRect(x: 0, y: -1080, width: 1920, height: 1055)
        let rect = CGRect(x: 1900, y: -1200, width: 64, height: 330)
        let origin = ZoomPanelPlacement.keptOnScreen(rect, visibleFrames: [visible, below], fallback: visible)
        #expect(origin == CGPoint(x: 1920 - 64, y: -1080))
    }

    @Test func fractionalPositionsRoundToWholePoints() {
        let rect = CGRect(x: 100.4, y: 200.6, width: 64, height: 330)
        let origin = ZoomPanelPlacement.keptOnScreen(rect, visibleFrames: [visible], fallback: visible)
        #expect(origin == CGPoint(x: 100, y: 201))
    }
}
