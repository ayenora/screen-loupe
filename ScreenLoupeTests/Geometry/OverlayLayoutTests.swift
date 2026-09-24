import CoreGraphics
import Testing

private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

private func layout(_ capture: CGRect, tabWidth: CGFloat = 180, labelWidth: CGFloat = 60) -> OverlayLayout {
    OverlayLayout(captureRect: capture, screenFrame: screen, tabWidth: tabWidth, labelWidth: labelWidth)
}

struct OverlayLayoutTests {
    @Test func tabSitsCentredAboveTheFrame() {
        let l = layout(CGRect(x: 100, y: 100, width: 200, height: 100))
        #expect(l.tabPlacement == .above)
        #expect(l.tabRect == CGRect(x: 110, y: 210, width: 180, height: 22))
    }

    @Test func tabMovesBelowWhenThereIsNoRoomAbove() {
        let l = layout(CGRect(x: 100, y: 800, width: 200, height: 95))
        #expect(l.tabPlacement == .below)
        #expect(l.tabRect.minY == 768)
    }

    @Test func tabGoesInsideWhenTheFrameFillsTheScreenHeight() {
        let l = layout(CGRect(x: 100, y: 0, width: 200, height: 900))
        #expect(l.tabPlacement == .inside)
        #expect(l.tabRect.maxY == CGFloat(888))
    }

    @Test func tabInsideAFrameTallerThanTheScreenStaysOnScreen() {
        let l = layout(CGRect(x: 100, y: -50, width: 200, height: 1000))
        #expect(l.tabPlacement == .inside)
        #expect(l.tabRect.maxY == CGFloat(888))
    }

    @Test(arguments: [
        // Near the left edge: slides right, 6 pt from the edge.
        (CGRect(x: 2, y: 300, width: 100, height: 50), CGFloat(6)),
        // Near the right edge: slides left.
        (CGRect(x: 1400, y: 300, width: 40, height: 50), CGFloat(1440 - 6 - 180)),
    ])
    func tabStaysOffTheScreenEdges(capture: CGRect, expectedX: CGFloat) {
        #expect(layout(capture).tabRect.minX == expectedX)
    }

    @Test func labelSitsBelowOnTheRight() {
        let l = layout(CGRect(x: 100, y: 100, width: 200, height: 100))
        #expect(l.labelRect == CGRect(x: 240, y: 78, width: 60, height: 16))
    }

    @Test func labelGoesInsideWhenThereIsNoRoomBelow() {
        let l = layout(CGRect(x: 100, y: 10, width: 200, height: 100))
        #expect(l.labelRect.minY == 16)
    }

    @Test(arguments: [
        CGRect(x: 100, y: 100, width: 200, height: 100),
        CGRect(x: 2, y: 850, width: 30, height: 40),
        CGRect(x: 100, y: 0, width: 200, height: 900),
    ])
    func windowHoldsEveryPart(capture: CGRect) {
        let l = layout(capture)
        #expect(l.windowFrame.contains(l.captureRect.insetBy(dx: -6, dy: -6)))
        #expect(l.windowFrame.contains(l.tabRect))
        #expect(l.windowFrame.contains(l.labelRect))
    }

    @Test(arguments: [
        (CGPoint(x: 100, y: 200), OverlayHitTarget?.some(.resize(.topLeft))),
        (CGPoint(x: 300, y: 150), .resize(.right)),
        (CGPoint(x: 200, y: 99), .resize(.bottom)),
        // The band outside the line, away from the handles.
        (CGPoint(x: 97, y: 120), .move),
        (CGPoint(x: 250, y: 203), .move),
        // The tab.
        (CGPoint(x: 200, y: 220), .move),
        // Inside the frame: the click goes to the app underneath.
        (CGPoint(x: 150, y: 150), nil),
        (CGPoint(x: 20, y: 20), nil),
    ])
    func hitTargets(point: CGPoint, expected: OverlayHitTarget?) {
        #expect(layout(CGRect(x: 100, y: 100, width: 200, height: 100)).hitTarget(at: point) == expected)
    }

    @Test(arguments: [
        (CGPoint(x: 95, y: 150), true),
        (CGPoint(x: 310, y: 150), true),
        (CGPoint(x: 200, y: 220), true),
        (CGPoint(x: 150, y: 150), false),
        (CGPoint(x: 400, y: 150), false),
    ])
    func hoverZoneHugsTheLine(point: CGPoint, expected: Bool) {
        #expect(layout(CGRect(x: 100, y: 100, width: 200, height: 100)).isInHoverZone(point) == expected)
    }
}

struct CaptureAreaEditingTests {
    let rect = CGRect(x: 100, y: 100, width: 200, height: 100)

    @Test func cornerHandleMovesTwoEdges() {
        let r = CaptureAreaEditing.resized(rect, handle: .topLeft, by: CGVector(dx: -10, dy: 5))
        #expect(r == CGRect(x: 90, y: 100, width: 210, height: 105))
    }

    @Test func resizingStopsAtTheMinimumSize() {
        let narrow = CaptureAreaEditing.resized(rect, handle: .right, by: CGVector(dx: -500, dy: 0))
        #expect(narrow == CGRect(x: 100, y: 100, width: 64, height: 100))
        let short = CaptureAreaEditing.resized(rect, handle: .bottom, by: CGVector(dx: 0, dy: 500))
        #expect(short == CGRect(x: 100, y: 136, width: 200, height: 64))
    }

    @Test(arguments: [
        (CaptureAreaEditing.ArrowKey.left, false, CGRect(x: 99.5, y: 100, width: 200, height: 100)),
        (.up, false, CGRect(x: 100, y: 100.5, width: 200, height: 100)),
        (.right, true, CGRect(x: 100, y: 100, width: 200.5, height: 100)),
        (.left, true, CGRect(x: 100, y: 100, width: 199.5, height: 100)),
        // Resizing keeps the top edge (maxY = 200) in place.
        (.down, true, CGRect(x: 100, y: 99.5, width: 200, height: 100.5)),
        (.up, true, CGRect(x: 100, y: 100.5, width: 200, height: 99.5)),
    ])
    func arrowKeys(key: CaptureAreaEditing.ArrowKey, resize: Bool, expected: CGRect) {
        #expect(CaptureAreaEditing.nudged(rect, key: key, step: 0.5, resize: resize) == expected)
    }
}

struct OverlayPositionBoxTests {
    private let box = CGSize(width: 50, height: 60)

    @Test func boxSitsRightOfTheFrameLevelWithItsTop() {
        let l = OverlayLayout(
            captureRect: CGRect(x: 100, y: 100, width: 200, height: 100), screenFrame: screen, tabWidth: 180,
            labelWidth: 60, positionSize: box)
        #expect(l.positionRect == CGRect(x: 312, y: 140, width: 50, height: 60))
    }

    @Test func boxFlipsLeftWhenTheRightSideIsOffScreen() {
        let l = OverlayLayout(
            captureRect: CGRect(x: 1200, y: 100, width: 220, height: 100), screenFrame: screen, tabWidth: 180,
            labelWidth: 60, positionSize: box)
        #expect(l.positionRect.maxX == CGFloat(1200 - 12))
    }

    @Test func boxStaysOnScreenBelowAFrameAtTheTop() {
        let l = OverlayLayout(
            captureRect: CGRect(x: 100, y: 870, width: 200, height: 30), screenFrame: screen, tabWidth: 180,
            labelWidth: 60, positionSize: box)
        #expect(l.positionRect.maxY == CGFloat(900 - 6))
    }

    @Test func pinnedFrameOnlyAnswersThePinButton() {
        let l = layout(CGRect(x: 100, y: 100, width: 200, height: 100))
        #expect(l.hitTarget(at: CGPoint(x: l.pinRect.midX, y: l.pinRect.midY), pinned: true) == .pin)
        #expect(l.hitTarget(at: CGPoint(x: l.tabRect.minX + 5, y: l.tabRect.midY), pinned: true) == nil)
        #expect(l.hitTarget(at: CGPoint(x: 100, y: 100), pinned: true) == nil)
        #expect(l.hitTarget(at: CGPoint(x: 100, y: 100)) == .resize(.bottomLeft))
    }
}
