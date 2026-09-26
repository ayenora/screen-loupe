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

    // The wider side (200) decides; the corner opposite the handle stays put.
    @Test(arguments: [
        (OverlayHandle.topLeft, CGRect(x: 100, y: 100, width: 200, height: 200)),
        (.topRight, CGRect(x: 100, y: 100, width: 200, height: 200)),
        (.bottomLeft, CGRect(x: 100, y: 0, width: 200, height: 200)),
        (.bottomRight, CGRect(x: 100, y: 0, width: 200, height: 200)),
    ])
    func shiftOnACornerSquaresTheArea(handle: OverlayHandle, expected: CGRect) {
        #expect(CaptureAreaEditing.squared(rect, handle: handle) == expected)
    }

    // The taller side (150) decides, so only the dragged vertical edge moves.
    @Test(arguments: [
        (OverlayHandle.topLeft, CGRect(x: 30, y: 100, width: 150, height: 150)),
        (.topRight, CGRect(x: 100, y: 100, width: 150, height: 150)),
        (.bottomLeft, CGRect(x: 30, y: 100, width: 150, height: 150)),
        (.bottomRight, CGRect(x: 100, y: 100, width: 150, height: 150)),
    ])
    func theTallerSideDecidesToo(handle: OverlayHandle, expected: CGRect) {
        let tall = CGRect(x: 100, y: 100, width: 80, height: 150)
        #expect(CaptureAreaEditing.squared(tall, handle: handle) == expected)
    }

    @Test func halfPointEdgesOnRetinaStayOnTheGrid() {
        let retina = CGRect(x: 100.5, y: 100, width: 80.5, height: 150)
        #expect(
            CaptureAreaEditing.squared(retina, handle: .bottomLeft) == CGRect(x: 31, y: 100, width: 150, height: 150))
    }

    @Test(arguments: [OverlayHandle.top, .bottom, .left, .right])
    func shiftOnAnEdgeChangesNothing(handle: OverlayHandle) {
        #expect(CaptureAreaEditing.squared(rect, handle: handle) == rect)
    }

    @Test func aMinimumWidthGrowsToTheHeight() {
        let narrow = CGRect(x: 100, y: 100, width: 64, height: 120)
        #expect(
            CaptureAreaEditing.squared(narrow, handle: .bottomRight) == CGRect(x: 100, y: 100, width: 120, height: 120))
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

    @Test func pinnedFrameOnlyAnswersItsButtons() {
        let l = layout(CGRect(x: 100, y: 100, width: 200, height: 100))
        #expect(l.hitTarget(at: CGPoint(x: l.pinRect.midX, y: l.pinRect.midY), lock: .pinned) == .pin)
        #expect(l.hitTarget(at: CGPoint(x: l.pinMenuRect.midX, y: l.pinMenuRect.midY), lock: .pinned) == .pinMenu)
        #expect(l.hitTarget(at: CGPoint(x: l.tabRect.minX + 5, y: l.tabRect.midY), lock: .pinned) == nil)
        #expect(l.hitTarget(at: CGPoint(x: 100, y: 100), lock: .pinned) == nil)
        #expect(l.hitTarget(at: CGPoint(x: 100, y: 100)) == .resize(.bottomLeft))
        #expect(l.hitTarget(at: CGPoint(x: l.raiseRect.midX, y: l.raiseRect.midY), lock: .pinned) == .raiseViewer)
        #expect(l.hitTarget(at: CGPoint(x: l.pickRect.midX, y: l.pickRect.midY), lock: .pinned) == .pickWindow)
    }

    @Test(arguments: [
        // Every handle still resizes.
        (CGPoint(x: 100, y: 200), OverlayHitTarget?.some(.resize(.topLeft))),
        (CGPoint(x: 300, y: 150), .resize(.right)),
        (CGPoint(x: 200, y: 99), .resize(.bottom)),
        (CGPoint(x: 300, y: 100), .resize(.bottomRight)),
        // The band and the tab don't move it: the press goes to the app underneath.
        (CGPoint(x: 97, y: 120), nil),
        (CGPoint(x: 250, y: 203), nil),
        (CGPoint(x: 200, y: 220), nil),
        (CGPoint(x: 150, y: 150), nil),
    ])
    func fixedPositionFrameResizesButDoesNotMove(point: CGPoint, expected: OverlayHitTarget?) {
        let l = layout(CGRect(x: 100, y: 100, width: 200, height: 100))
        #expect(l.hitTarget(at: point, lock: .fixedPosition) == expected)
        // An attached magnet takes the same presses: only its window moves it.
        #expect(l.hitTarget(at: point, lock: .magnet) == expected)
    }

    @Test func fixedPositionFrameAnswersItsButtons() {
        let l = layout(CGRect(x: 100, y: 100, width: 200, height: 100))
        #expect(l.hitTarget(at: CGPoint(x: l.pinRect.midX, y: l.pinRect.midY), lock: .fixedPosition) == .pin)
        #expect(
            l.hitTarget(at: CGPoint(x: l.pinMenuRect.midX, y: l.pinMenuRect.midY), lock: .fixedPosition) == .pinMenu)
        #expect(
            l.hitTarget(at: CGPoint(x: l.pickRect.midX, y: l.pickRect.midY), lock: .fixedPosition) == .pickWindow)
    }

    @Test func onlyPinnedBlocksResizing() {
        #expect(!CaptureAreaLock.pinned.allowsResize)
        #expect(CaptureAreaLock.fixedPosition.allowsResize)
        #expect(CaptureAreaLock.magnet.allowsResize)
    }

    @Test func arrowKeysOnlyResizeAFixedPositionOrMagnetFrame() {
        #expect(!CaptureAreaLock.pinned.allowsNudge(resizing: false))
        #expect(!CaptureAreaLock.pinned.allowsNudge(resizing: true))
        #expect(!CaptureAreaLock.fixedPosition.allowsNudge(resizing: false))
        #expect(CaptureAreaLock.fixedPosition.allowsNudge(resizing: true))
        #expect(!CaptureAreaLock.magnet.allowsNudge(resizing: false))
        #expect(CaptureAreaLock.magnet.allowsNudge(resizing: true))
    }

    @Test func theButtonsFollowThePinAwayFromTheTab() {
        let l = layout(CGRect(x: 100, y: 100, width: 200, height: 100))
        #expect(l.pinRect.minX == l.tabRect.maxX + 4)
        #expect(l.pinMenuRect == CGRect(x: l.pinRect.maxX, y: l.pinRect.minY, width: 13, height: 22))
        #expect(l.raiseRect.minX == l.pinMenuRect.maxX + 4)
        #expect(l.pickRect.minX == l.raiseRect.maxX + 4)
        #expect(l.pickRect.minY == l.tabRect.minY)
        #expect(l.isInHoverZone(CGPoint(x: l.pinMenuRect.midX, y: l.pinMenuRect.midY)))
    }

    @Test func atTheRightEdgeAllButtonsMoveLeftOfTheTab() {
        // The tab hugs the right margin: no room for the buttons on its right. The ▾ stays on the
        // pin's right, between it and the tab.
        let l = layout(CGRect(x: 1300, y: 100, width: 134, height: 100))
        #expect(l.pinMenuRect.maxX == l.tabRect.minX - 4)
        #expect(l.pinMenuRect.minX == l.pinRect.maxX)
        #expect(l.raiseRect.maxX == l.pinRect.minX - 4)
        #expect(l.pickRect.maxX == l.raiseRect.minX - 4)
        #expect(l.windowFrame.contains(l.pickRect))
    }
}

struct OverlayNoticeTests {
    private func layout(_ capture: CGRect) -> OverlayLayout {
        OverlayLayout(captureRect: capture, screenFrame: screen, tabWidth: 180, labelWidth: 60, noticeWidth: 140)
    }

    @Test func noticeSitsLeftOfTheTabAwayFromTheButtons() {
        let l = layout(CGRect(x: 400, y: 100, width: 200, height: 100))
        #expect(l.noticeRect == CGRect(x: l.tabRect.minX - 4 - 140, y: l.tabRect.minY + 3, width: 140, height: 16))
        #expect(l.windowFrame.contains(l.noticeRect))
    }

    @Test func atTheLeftEdgeTheNoticeGoesPastThePickButton() {
        let l = layout(CGRect(x: 10, y: 100, width: 200, height: 100))
        #expect(l.noticeRect.minX == l.pickRect.maxX + 4)
        #expect(l.windowFrame.contains(l.noticeRect))
    }

    @Test func atTheRightEdgeTheNoticeGoesPastThePickButtonOnTheLeft() {
        let l = layout(CGRect(x: 1300, y: 100, width: 134, height: 100))
        #expect(l.noticeRect.maxX == l.pickRect.minX - 4)
        #expect(l.noticeRect.minX >= 6)
        #expect(l.windowFrame.contains(l.noticeRect))
    }

    @Test func noNoticeTakesNoRoom() {
        let capture = CGRect(x: 400, y: 100, width: 200, height: 100)
        let plain = OverlayLayout(captureRect: capture, screenFrame: screen, tabWidth: 180, labelWidth: 60)
        #expect(plain.noticeRect == .zero)
        #expect(plain.windowFrame == layout(capture).windowFrame.intersection(plain.windowFrame))
    }
}
