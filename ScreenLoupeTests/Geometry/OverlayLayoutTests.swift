import CoreGraphics
import Foundation
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

    // MARK: The viewport handle

    @Test(arguments: [
        // A 30 × 18 pill centred on the part's top edge (y 160): from (160, 151) to (190, 169).
        (CGPoint(x: 175, y: 160), OverlayHitTarget?.some(.viewportHandle)),
        // Its bottom-left corner and left edge take the press; its right and top edges don't, as
        // `CGRect.contains` counts them.
        (CGPoint(x: 160, y: 151), .viewportHandle),
        (CGPoint(x: 160, y: 165), .viewportHandle),
        (CGPoint(x: 189.9, y: 168.9), .viewportHandle),
        (CGPoint(x: 190, y: 160), nil),
        (CGPoint(x: 175, y: 169), nil),
        (CGPoint(x: 159.9, y: 160), nil),
        (CGPoint(x: 175, y: 150.9), nil),
        // Elsewhere inside the part and the area the press goes to the app underneath.
        (CGPoint(x: 175, y: 130), nil),
        (CGPoint(x: 250, y: 150), nil),
    ])
    func viewportHandleTakesPressesOnlyInsideIt(point: CGPoint, expected: OverlayHitTarget?) {
        let l = layout(CGRect(x: 100, y: 100, width: 200, height: 100))
        let handle = l.viewportHandleRect(for: CGRect(x: 150, y: 120, width: 50, height: 40))
        #expect(handle == CGRect(x: 160, y: 151, width: 30, height: 18))
        // It moves the Viewer, not the area: every lock lets it.
        for lock in [nil, CaptureAreaLock.pinned, .fixedPosition, .magnet] {
            #expect(l.hitTarget(at: point, lock: lock, viewportHandle: handle) == expected)
        }
        // Without the handle nothing inside the area takes a press.
        #expect(l.hitTarget(at: point) == nil)
    }

    @Test(arguments: [
        // Part, then the handle: centred on the part's top edge.
        (CGRect(x: 150, y: 120, width: 50, height: 40), CGRect(x: 160, y: 151, width: 30, height: 18)),
        // The part's top is the area's top: the handle sits just inside.
        (CGRect(x: 150, y: 150, width: 50, height: 50), CGRect(x: 160, y: 182, width: 30, height: 18)),
        // A top edge 3 pt under the area's: still inside, not sticking out.
        (CGRect(x: 150, y: 150, width: 50, height: 47), CGRect(x: 160, y: 182, width: 30, height: 18)),
        // Exactly half the pill under the area's top: centred, touching it.
        (CGRect(x: 150, y: 150, width: 50, height: 41), CGRect(x: 160, y: 182, width: 30, height: 18)),
        (CGRect(x: 150, y: 150, width: 50, height: 40), CGRect(x: 160, y: 181, width: 30, height: 18)),
        // A narrow part at a side of the area: the handle stays within the area's sides.
        (CGRect(x: 100, y: 120, width: 10, height: 40), CGRect(x: 100, y: 151, width: 30, height: 18)),
        (CGRect(x: 290, y: 120, width: 10, height: 40), CGRect(x: 270, y: 151, width: 30, height: 18)),
        // Half-point edges on a 2× display.
        (CGRect(x: 150.5, y: 120, width: 50, height: 40.5), CGRect(x: 160.5, y: 151.5, width: 30, height: 18)),
    ])
    func viewportHandleSitsOnThePartsTopEdgeInsideTheArea(part: CGRect, expected: CGRect) {
        let l = layout(CGRect(x: 100, y: 100, width: 200, height: 100))
        let handle = l.viewportHandleRect(for: part)
        #expect(handle == expected)
        #expect(l.captureRect.contains(handle))
    }

    @Test func viewportHandleOnADisplayAtNegativeCoordinates() {
        let screen = CGRect(x: -2560, y: -180, width: 2560, height: 1440)
        let l = OverlayLayout(
            captureRect: CGRect(x: -500, y: -150, width: 200, height: 100), screenFrame: screen, tabWidth: 180,
            labelWidth: 60)
        let handle = l.viewportHandleRect(for: CGRect(x: -450, y: -120, width: 100, height: 70))
        #expect(handle == CGRect(x: -415, y: -68, width: 30, height: 18))
        #expect(l.hitTarget(at: CGPoint(x: -400, y: -60), viewportHandle: handle) == .viewportHandle)
        #expect(l.hitTarget(at: CGPoint(x: -400, y: -100), viewportHandle: handle) == nil)
    }

    @Test func viewportHandleWinsOverTheResizeHandlesAndTheTabButNotTheButtons() {
        // A tall area: the tab sits inside at the top, where the handle of a part reaching the top is.
        let l = layout(CGRect(x: 100, y: 0, width: 200, height: 900))
        #expect(l.tabPlacement == .inside)
        let handle = l.viewportHandleRect(for: CGRect(x: 100, y: 450, width: 200, height: 450))
        #expect(handle == CGRect(x: 185, y: 882, width: 30, height: 18))
        #expect(l.hitTarget(at: CGPoint(x: 200, y: 895), viewportHandle: handle) == .viewportHandle)
        #expect(l.hitTarget(at: CGPoint(x: 200, y: 895)) == .resize(.top))
        #expect(l.hitTarget(at: CGPoint(x: 200, y: 885), viewportHandle: handle) == .viewportHandle)
        #expect(l.hitTarget(at: CGPoint(x: 200, y: 885)) == .move)
        #expect(
            l.hitTarget(at: CGPoint(x: l.pinRect.midX, y: l.pinRect.midY), viewportHandle: l.pinRect) == .pin)
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
        #expect(l.viewportRect == CGRect(x: l.pinMenuRect.maxX + 4, y: l.pinRect.minY, width: 22, height: 22))
        #expect(l.raiseRect.minX == l.viewportRect.maxX + 4)
        #expect(l.pickRect.minX == l.raiseRect.maxX + 4)
        #expect(l.pickRect.minY == l.tabRect.minY)
        #expect(l.isInHoverZone(CGPoint(x: l.pinMenuRect.midX, y: l.pinMenuRect.midY)))
        #expect(l.isInHoverZone(CGPoint(x: l.viewportRect.midX, y: l.viewportRect.midY)))
        #expect(l.hitTarget(at: CGPoint(x: l.viewportRect.midX, y: l.viewportRect.midY)) == .viewportButton)
        #expect(
            l.hitTarget(at: CGPoint(x: l.viewportRect.midX, y: l.viewportRect.midY), lock: .pinned) == .viewportButton)
    }

    @Test func atTheRightEdgeAllButtonsMoveLeftOfTheTab() {
        // The tab hugs the right margin: no room for the buttons on its right. The ▾ stays on the
        // pin's right, between it and the tab.
        let l = layout(CGRect(x: 1300, y: 100, width: 134, height: 100))
        #expect(l.pinMenuRect.maxX == l.tabRect.minX - 4)
        #expect(l.pinMenuRect.minX == l.pinRect.maxX)
        #expect(l.viewportRect.maxX == l.pinRect.minX - 4)
        #expect(l.raiseRect.maxX == l.viewportRect.minX - 4)
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

/// The Screenshot studio's frame: the pick button alone beside the tab.
struct OverlayLayoutWithoutLockButtonsTests {
    private func layout(_ capture: CGRect) -> OverlayLayout {
        OverlayLayout(
            captureRect: capture, screenFrame: screen, tabWidth: 180, labelWidth: 60, noticeWidth: 140,
            lockButtons: false)
    }

    @Test func thePickButtonSitsBesideTheTab() {
        let l = layout(CGRect(x: 400, y: 100, width: 200, height: 100))
        #expect(l.pickRect == CGRect(x: l.tabRect.maxX + 4, y: l.tabRect.minY, width: 22, height: 22))
        #expect(l.pinRect.isNull)
        #expect(l.pinMenuRect.isNull)
        #expect(l.viewportRect.isNull)
        #expect(l.raiseRect.isNull)
        #expect(l.hitTarget(at: CGPoint(x: l.pickRect.midX, y: l.pickRect.midY)) == .pickWindow)
        #expect(l.isInHoverZone(CGPoint(x: l.pickRect.midX, y: l.pickRect.midY)))
    }

    @Test func atTheRightEdgeThePickButtonMovesLeftOfTheTab() {
        let l = layout(CGRect(x: 1300, y: 100, width: 134, height: 100))
        #expect(l.pickRect.maxX == l.tabRect.minX - 4)
        #expect(l.noticeRect.maxX == l.pickRect.minX - 4)
    }

    @Test func theNoticeSitsLeftOfTheTab() {
        let l = layout(CGRect(x: 400, y: 100, width: 200, height: 100))
        #expect(l.noticeRect.maxX == l.tabRect.minX - 4)
        #expect(l.windowFrame.contains(l.noticeRect))
    }

    @Test func theWindowHoldsOnlyTheFrameAndItsParts() {
        let capture = CGRect(x: 400, y: 100, width: 200, height: 100)
        let l = OverlayLayout(
            captureRect: capture, screenFrame: screen, tabWidth: 180, labelWidth: 60, lockButtons: false)
        #expect(l.windowFrame == capture.insetBy(dx: -40, dy: -40).union(l.tabRect.insetBy(dx: -8, dy: -8)).integral)
    }

    @Test func handlesAndTheBandStillWork() {
        let l = layout(CGRect(x: 100, y: 100, width: 200, height: 100))
        #expect(l.hitTarget(at: CGPoint(x: 300, y: 100)) == .resize(.bottomRight))
        #expect(l.hitTarget(at: CGPoint(x: 97, y: 120)) == .move)
        #expect(l.hitTarget(at: CGPoint(x: l.tabRect.midX, y: l.tabRect.midY)) == .move)
        #expect(l.hitTarget(at: CGPoint(x: 150, y: 150)) == nil)
    }
}

struct SavedPinTests {
    private func savedPin(_ json: String) throws -> Bool? {
        try JSONDecoder().decode(CaptureAreaLock.SavedPin.self, from: Data(json.utf8)).isOn
    }

    @Test(arguments: [true, false])
    func theLockIsReadAsSaved(_ locked: Bool) throws {
        #expect(try savedPin(#"{"captureAreaLocked": \#(locked)}"#) == locked)
    }

    @Test(arguments: [true, false])
    func aPinSavedBeforeTheLocksCarriesOver(_ pinned: Bool) throws {
        #expect(try savedPin(#"{"captureAreaPinned": \#(pinned)}"#) == pinned)
    }

    @Test func theLockWinsOverTheOldPin() throws {
        #expect(try savedPin(#"{"captureAreaLocked": false, "captureAreaPinned": true}"#) == false)
        #expect(try savedPin(#"{"captureAreaLocked": true, "captureAreaPinned": false}"#) == true)
    }

    @Test func anUnreadableLockFallsBackToTheOldPin() throws {
        #expect(try savedPin(#"{"captureAreaLocked": "yes", "captureAreaPinned": true}"#) == true)
    }

    @Test func nothingReadableIsNil() throws {
        #expect(try savedPin("{}") == nil)
        #expect(try savedPin(#"{"captureAreaLocked": 2, "captureAreaPinned": "on"}"#) == nil)
    }
}
