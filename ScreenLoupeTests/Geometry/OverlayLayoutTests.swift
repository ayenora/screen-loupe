import CoreGraphics
import Foundation
import Testing

private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

private func layout(_ capture: CGRect, tabWidth: CGFloat = 180, labelWidth: CGFloat = 60) -> OverlayLayout {
    OverlayLayout(captureRect: capture, screenFrame: screen, tabWidth: tabWidth, labelWidth: labelWidth)
}

/// With "»" clicked: every button shows.
private func expanded(_ capture: CGRect) -> OverlayLayout {
    OverlayLayout(captureRect: capture, screenFrame: screen, tabWidth: 180, labelWidth: 60, buttonsExpanded: true)
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

    private let area = CGRect(x: 100, y: 100, width: 200, height: 100)

    @Test(arguments: [
        // A 30 × 18 pill 2 pt above the part (whose top is y 160): from (160, 162) to (190, 180).
        (CGPoint(x: 175, y: 170), OverlayHitTarget?.some(.viewportHandle)),
        // Its bottom-left corner and left edge take the press; its right and top edges don't, as
        // `CGRect.contains` counts them.
        (CGPoint(x: 160, y: 162), .viewportHandle),
        (CGPoint(x: 160, y: 170), .viewportHandle),
        (CGPoint(x: 189.9, y: 179.9), .viewportHandle),
        (CGPoint(x: 190, y: 170), nil),
        (CGPoint(x: 175, y: 180), nil),
        (CGPoint(x: 159.9, y: 170), nil),
        // The gap between it and the part, the part, and the rest of the area: the app underneath.
        (CGPoint(x: 175, y: 161), nil),
        (CGPoint(x: 175, y: 130), nil),
        (CGPoint(x: 250, y: 150), nil),
    ])
    func viewportHandleTakesPressesOnlyInsideIt(point: CGPoint, expected: OverlayHitTarget?) throws {
        let l = layout(area)
        let handle = try #require(l.viewportHandleRect(for: CGRect(x: 150, y: 120, width: 50, height: 40)))
        #expect(handle == CGRect(x: 160, y: 162, width: 30, height: 18))
        // It moves the Viewer, not the area: every lock lets it.
        for lock in [nil, CaptureAreaLock.pinned, .fixedPosition, .magnet] {
            #expect(l.hitTarget(at: point, lock: lock, viewportHandle: handle) == expected)
        }
        // Without the handle nothing inside the area takes a press.
        #expect(l.hitTarget(at: point) == nil)
    }

    @Test(arguments: [
        // Part, then the handle. A large part: above it, centred, 2 pt off.
        (CGRect(x: 150, y: 120, width: 50, height: 40), CGRect(x: 160, y: 162, width: 30, height: 18)),
        // A tiny part, smaller than the pill (6400 %): above it all the same, never over it.
        (CGRect(x: 200, y: 150, width: 4, height: 2), CGRect(x: 187, y: 154, width: 30, height: 18)),
        // At the area's top edge, or too close to it: below.
        (CGRect(x: 150, y: 150, width: 50, height: 50), CGRect(x: 160, y: 130, width: 30, height: 18)),
        (CGRect(x: 150, y: 150, width: 50, height: 31), CGRect(x: 160, y: 130, width: 30, height: 18)),
        // Exactly room above: still above.
        (CGRect(x: 150, y: 150, width: 50, height: 30), CGRect(x: 160, y: 182, width: 30, height: 18)),
        // From the top to the bottom: at the left, centred on it vertically; no room left: at the right.
        (CGRect(x: 150, y: 100, width: 50, height: 100), CGRect(x: 118, y: 141, width: 30, height: 18)),
        (CGRect(x: 110, y: 100, width: 50, height: 100), CGRect(x: 162, y: 141, width: 30, height: 18)),
        // In the top-left and top-right corners: below, kept within the area's sides.
        (CGRect(x: 100, y: 160, width: 20, height: 40), CGRect(x: 100, y: 140, width: 30, height: 18)),
        (CGRect(x: 280, y: 160, width: 20, height: 40), CGRect(x: 270, y: 140, width: 30, height: 18)),
        // In the bottom-right corner: above, kept within the right side.
        (CGRect(x: 290, y: 100, width: 10, height: 10), CGRect(x: 270, y: 112, width: 30, height: 18)),
        // Half-point edges on a 2× display.
        (CGRect(x: 150.5, y: 120, width: 50, height: 40.5), CGRect(x: 160.5, y: 162.5, width: 30, height: 18)),
        (CGRect(x: 150.5, y: 150.5, width: 50, height: 49.5), CGRect(x: 160.5, y: 130.5, width: 30, height: 18)),
    ])
    func viewportHandleSitsBesideThePartInsideTheArea(part: CGRect, expected: CGRect) throws {
        let l = layout(area)
        let handle = try #require(l.viewportHandleRect(for: part))
        #expect(handle == expected)
        #expect(l.captureRect.contains(handle))
        #expect(!handle.intersects(part))
    }

    @Test func noViewportHandleWhereItFitsNowhere() {
        // The part leaves under 20 pt above and below and under 32 pt at either side.
        #expect(layout(area).viewportHandleRect(for: CGRect(x: 105, y: 100, width: 190, height: 100)) == nil)
    }

    @Test func viewportHandleOnADisplayAtNegativeCoordinates() throws {
        let screen = CGRect(x: -2560, y: -180, width: 2560, height: 1440)
        let l = OverlayLayout(
            captureRect: CGRect(x: -500, y: -150, width: 200, height: 100), screenFrame: screen, tabWidth: 180,
            labelWidth: 60)
        // The part reaches the area's top: below it.
        let part = CGRect(x: -450, y: -120, width: 100, height: 70)
        let handle = try #require(l.viewportHandleRect(for: part))
        #expect(handle == CGRect(x: -415, y: -140, width: 30, height: 18))
        #expect(l.hitTarget(at: CGPoint(x: -400, y: -130), viewportHandle: handle) == .viewportHandle)
        #expect(l.hitTarget(at: CGPoint(x: -400, y: -100), viewportHandle: handle) == nil)
    }

    @Test(arguments: [
        CGRect(x: 100, y: 100, width: 200, height: 100), CGRect(x: -600.5, y: -300.5, width: 120, height: 64),
    ])
    func viewportHandleNeverCoversThePart(area: CGRect) {
        let l = layout(area)
        let steps: [CGFloat] = [0, 0.25, 0.5, 0.75, 1]
        let sizes: [CGFloat] = [0.5, 2, 4, 10, 25, 50, 90, 150, 200]
        for width in sizes where width <= area.width {
            for height in sizes where height <= area.height {
                for fx in steps {
                    for fy in steps {
                        let part = CGRect(
                            x: area.minX + (area.width - width) * fx, y: area.minY + (area.height - height) * fy,
                            width: width, height: height)
                        guard let handle = l.viewportHandleRect(for: part) else {
                            // Only a part leaving no room at any of its sides goes without.
                            #expect(area.maxY - part.maxY < 20 && part.minY - area.minY < 20)
                            #expect(part.minX - area.minX < 32 && area.maxX - part.maxX < 32)
                            continue
                        }
                        #expect(!handle.intersects(part))
                        #expect(area.contains(handle))
                    }
                }
            }
        }
    }

    @Test func viewportHandleWinsOverTheResizeHandlesAndTheTabButNotTheButtons() {
        // A tall area: the tab sits inside at the top; a handle placed there takes the press.
        let l = layout(CGRect(x: 100, y: 0, width: 200, height: 900))
        #expect(l.tabPlacement == .inside)
        let handle = CGRect(x: 185, y: 882, width: 30, height: 18)
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

    @Test func boxGoesLeftOfTheFrameWhenItWouldCoverTheAvoidedRectOnTheRight() {
        let palette = CGRect(x: 320, y: 0, width: 36, height: 500)
        let l = OverlayLayout(
            captureRect: CGRect(x: 100, y: 100, width: 200, height: 100), screenFrame: screen, tabWidth: 180,
            labelWidth: 60, positionSize: box, positionAvoiding: palette)
        #expect(l.positionRect == CGRect(x: 100 - 12 - 50, y: 140, width: 50, height: 60))
        #expect(!l.positionRect.intersects(palette))
    }

    @Test func boxStaysRightWhenTheAvoidedRectIsOnTheLeft() {
        let palette = CGRect(x: 30, y: 0, width: 36, height: 500)
        let l = OverlayLayout(
            captureRect: CGRect(x: 100, y: 100, width: 200, height: 100), screenFrame: screen, tabWidth: 180,
            labelWidth: 60, positionSize: box, positionAvoiding: palette)
        #expect(l.positionRect.minX == CGFloat(312))
    }

    @Test func boxGoesBeyondTheAvoidedRectWhenNeitherSideOfTheFrameIsFree() {
        // The frame at the screen's right edge, the palette left of it: no room on the right, and the
        // left side is the palette's.
        let frame = CGRect(x: 1200, y: 100, width: 220, height: 100)
        let palette = CGRect(x: 1200 - 32 - 36, y: 0, width: 36, height: 500)
        let l = OverlayLayout(
            captureRect: frame, screenFrame: screen, tabWidth: 180, labelWidth: 60, positionSize: box,
            positionAvoiding: palette)
        #expect(l.positionRect.maxX == palette.minX - 12)
        #expect(!l.positionRect.intersects(palette))
    }

    @Test func boxGoesBeyondAnAvoidedRectRightOfTheFrameAwayFromTheFrame() {
        // The frame at the screen's left edge, the palette right of it.
        let frame = CGRect(x: 10, y: 100, width: 300, height: 100)
        let palette = CGRect(x: 310 + 32, y: 0, width: 36, height: 500)
        let l = OverlayLayout(
            captureRect: frame, screenFrame: screen, tabWidth: 180, labelWidth: 60, positionSize: box,
            positionAvoiding: palette)
        #expect(l.positionRect.minX == palette.maxX + 12)
    }

    @Test func boxKeepsItsPlaceWhenThereIsNoFreeRoom() {
        // A palette as wide as the screen: nowhere is free, so the box goes where it would anyway.
        let palette = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let l = OverlayLayout(
            captureRect: CGRect(x: 100, y: 100, width: 200, height: 100), screenFrame: screen, tabWidth: 180,
            labelWidth: 60, positionSize: box, positionAvoiding: palette)
        #expect(l.positionRect.minX == CGFloat(312))
    }

    @Test func boxOnADisplayWithNegativeCoordinatesAvoidsTheRect() {
        let display = CGRect(x: -1920, y: -300, width: 1920, height: 1080)
        let frame = CGRect(x: -1500, y: -100, width: 800, height: 500)
        let palette = CGRect(x: -668, y: 0, width: 36, height: 400)
        let l = OverlayLayout(
            captureRect: frame, screenFrame: display, tabWidth: 180, labelWidth: 60, positionSize: box,
            positionAvoiding: palette)
        #expect(l.positionRect.maxX == frame.minX - 12)
        #expect(!l.positionRect.intersects(palette))
    }

    @Test func boxAvoidsNothingByDefault() {
        let frame = CGRect(x: 100, y: 100, width: 200, height: 100)
        let plain = OverlayLayout(
            captureRect: frame, screenFrame: screen, tabWidth: 180, labelWidth: 60, positionSize: box)
        let avoidingNull = OverlayLayout(
            captureRect: frame, screenFrame: screen, tabWidth: 180, labelWidth: 60, positionSize: box,
            positionAvoiding: .null)
        #expect(plain.positionRect == avoidingNull.positionRect)
    }

    @Test func pinnedFrameOnlyAnswersItsButtons() {
        let l = expanded(CGRect(x: 100, y: 100, width: 200, height: 100))
        #expect(l.hitTarget(at: CGPoint(x: l.pinRect.midX, y: l.pinRect.midY), lock: .pinned) == .pin)
        #expect(l.hitTarget(at: CGPoint(x: l.pinMenuRect.midX, y: l.pinMenuRect.midY), lock: .pinned) == .pinMenu)
        #expect(l.hitTarget(at: CGPoint(x: l.tabRect.minX + 5, y: l.tabRect.midY), lock: .pinned) == nil)
        #expect(l.hitTarget(at: CGPoint(x: 100, y: 100), lock: .pinned) == nil)
        #expect(l.hitTarget(at: CGPoint(x: 100, y: 100)) == .resize(.bottomLeft))
        #expect(l.hitTarget(at: CGPoint(x: l.raiseRect.midX, y: l.raiseRect.midY), lock: .pinned) == .raiseViewer)
        #expect(l.hitTarget(at: CGPoint(x: l.pickRect.midX, y: l.pickRect.midY), lock: .pinned) == .pickWindow)
        let collapsed = layout(CGRect(x: 100, y: 100, width: 200, height: 100))
        #expect(
            collapsed.hitTarget(at: CGPoint(x: collapsed.moreRect.midX, y: collapsed.moreRect.midY), lock: .pinned)
                == .moreButtons)
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
        // An attached magnet takes the same presses, and its tab moves it.
        let tab = CGPoint(x: 200, y: 220)
        #expect(l.hitTarget(at: point, lock: .magnet) == (point == tab ? .move : expected))
    }

    @Test func onlyTheMagnetMovesByTheTab() {
        #expect(!CaptureAreaLock.pinned.movesByTab)
        #expect(!CaptureAreaLock.fixedPosition.movesByTab)
        #expect(CaptureAreaLock.magnet.movesByTab)
    }

    @Test(arguments: [
        // The handles, the line and the band: the press goes to the window under the frame.
        (CGPoint(x: 100, y: 200), OverlayHitTarget?.none),
        (CGPoint(x: 300, y: 150), nil),
        (CGPoint(x: 200, y: 99), nil),
        (CGPoint(x: 300, y: 100), nil),
        (CGPoint(x: 100.5, y: 150), nil),
        (CGPoint(x: 97, y: 120), nil),
        (CGPoint(x: 250, y: 203), nil),
        (CGPoint(x: 150, y: 150), nil),
        (CGPoint(x: 20, y: 20), nil),
        // The tab still moves it.
        (CGPoint(x: 200, y: 220), .move),
        (CGPoint(x: 111, y: 211), .move),
    ])
    func aFittedFrameTakesOnlyItsTab(point: CGPoint, expected: OverlayHitTarget?) {
        let l = layout(CGRect(x: 100, y: 100, width: 200, height: 100))
        #expect(l.hitTarget(at: point, lock: .magnet, fitted: true) == expected)
    }

    @Test func aFittedFrameAnswersItsButtonsAndTheViewportHandle() throws {
        let l = expanded(CGRect(x: 100, y: 100, width: 200, height: 100))
        for (target, rect) in [
            (OverlayHitTarget.pin, l.pinRect), (.pinMenu, l.pinMenuRect), (.viewportButton, l.viewportRect),
            (.raiseViewer, l.raiseRect), (.pickWindow, l.pickRect),
        ] {
            #expect(l.hitTarget(at: CGPoint(x: rect.midX, y: rect.midY), lock: .magnet, fitted: true) == target)
        }
        let handle = try #require(l.viewportHandleRect(for: CGRect(x: 150, y: 120, width: 50, height: 40)))
        #expect(
            l.hitTarget(
                at: CGPoint(x: handle.midX, y: handle.midY), lock: .magnet, fitted: true, viewportHandle: handle)
                == .viewportHandle)
        // With the pill shown, a corner where a handle would be still takes nothing.
        #expect(l.hitTarget(at: CGPoint(x: 100, y: 100), lock: .magnet, fitted: true, viewportHandle: handle) == nil)
    }

    @Test func fixedPositionFrameAnswersItsButtons() {
        let l = expanded(CGRect(x: 100, y: 100, width: 200, height: 100))
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
        let l = expanded(CGRect(x: 100, y: 100, width: 200, height: 100))
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
        let l = expanded(CGRect(x: 1300, y: 100, width: 134, height: 100))
        #expect(l.pinMenuRect.maxX == l.tabRect.minX - 4)
        #expect(l.pinMenuRect.minX == l.pinRect.maxX)
        #expect(l.viewportRect.maxX == l.pinRect.minX - 4)
        #expect(l.raiseRect.maxX == l.viewportRect.minX - 4)
        #expect(l.pickRect.maxX == l.raiseRect.minX - 4)
        #expect(l.windowFrame.contains(l.pickRect))
    }
}

struct OverlayNoticeTests {
    private func layout(_ capture: CGRect, expanded: Bool = false, viewportHandleOn: Bool = false) -> OverlayLayout {
        OverlayLayout(
            captureRect: capture, screenFrame: screen, tabWidth: 180, labelWidth: 60, noticeWidth: 140,
            buttonsExpanded: expanded, viewportHandleOn: viewportHandleOn)
    }

    @Test func noticeSitsLeftOfTheTabAwayFromTheButtons() {
        let l = layout(CGRect(x: 400, y: 100, width: 200, height: 100))
        #expect(l.noticeRect == CGRect(x: l.tabRect.minX - 4 - 140, y: l.tabRect.minY + 3, width: 140, height: 16))
        #expect(l.windowFrame.contains(l.noticeRect))
    }

    @Test func atTheLeftEdgeTheNoticeGoesPastTheLastButtonShown() {
        let capture = CGRect(x: 10, y: 100, width: 200, height: 100)
        let collapsed = layout(capture)
        #expect(collapsed.noticeRect.minX == collapsed.moreRect.maxX + 4)
        let withViewport = layout(capture, viewportHandleOn: true)
        #expect(withViewport.noticeRect.minX == withViewport.moreRect.maxX + 4)
        let all = layout(capture, expanded: true)
        #expect(all.noticeRect.minX == all.pickRect.maxX + 4)
        for l in [collapsed, withViewport, all] {
            #expect(l.windowFrame.contains(l.noticeRect))
        }
    }

    @Test func atTheRightEdgeTheNoticeGoesPastTheLastButtonShownOnTheLeft() {
        let capture = CGRect(x: 1300, y: 100, width: 134, height: 100)
        let collapsed = layout(capture)
        #expect(collapsed.noticeRect.maxX == collapsed.moreRect.minX - 4)
        let all = layout(capture, expanded: true)
        #expect(all.noticeRect.maxX == all.pickRect.minX - 4)
        for l in [collapsed, all] {
            #expect(l.noticeRect.minX >= 6)
            #expect(l.windowFrame.contains(l.noticeRect))
        }
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

/// The buttons after the pin's ▾: "»" collapses the raise and pick buttons, and the viewport button
/// unless its mode is on; a click on "»" shows them in its place.
struct OverlayTabButtonsTests {
    private static let display = CGRect(x: -2560, y: -180, width: 2560, height: 1440)

    private func layout(
        _ capture: CGRect, on screenFrame: CGRect = screen, expanded: Bool = false, viewportHandleOn: Bool = false,
        lockButtons: Bool = true
    ) -> OverlayLayout {
        OverlayLayout(
            captureRect: capture, screenFrame: screenFrame, tabWidth: 180, labelWidth: 60,
            positionSize: CGSize(width: 50, height: 60), lockButtons: lockButtons, buttonsExpanded: expanded,
            viewportHandleOn: viewportHandleOn)
    }

    private func rect(_ target: OverlayHitTarget, in l: OverlayLayout) -> CGRect {
        switch target {
        case .viewportButton: l.viewportRect
        case .raiseViewer: l.raiseRect
        case .pickWindow: l.pickRect
        case .moreButtons: l.moreRect
        default: .null
        }
    }

    private static let rowTargets: [OverlayHitTarget] = [.viewportButton, .moreButtons, .raiseViewer, .pickWindow]

    @Test(arguments: [
        // Collapsed, expanded, viewport mode off and on.
        (false, false, [OverlayHitTarget.moreButtons]),
        (false, true, [.viewportButton, .moreButtons]),
        (true, false, [.viewportButton, .raiseViewer, .pickWindow]),
        (true, true, [.viewportButton, .raiseViewer, .pickWindow]),
    ])
    func theRowShowsWhatIsNotCollapsed(expanded: Bool, viewportHandleOn: Bool, row: [OverlayHitTarget]) {
        // Right of the tab, left of it at the screen's right edge, and on a display left of the main one.
        let places: [(CGRect, CGRect)] = [
            (CGRect(x: 100, y: 100, width: 200, height: 100), screen),
            (CGRect(x: 1300, y: 100, width: 134, height: 100), screen),
            (CGRect(x: -2000.5, y: 100.5, width: 300, height: 200), Self.display),
            (CGRect(x: -200, y: -100, width: 150, height: 100), Self.display),
        ]
        for (capture, screenFrame) in places {
            let l = layout(capture, on: screenFrame, expanded: expanded, viewportHandleOn: viewportHandleOn)
            #expect(l.rowButtons == row)
            for target in Self.rowTargets where !row.contains(target) {
                #expect(rect(target, in: l).isNull)
            }
            // Each one a step further from the tab, the first beside the pin's ▾.
            var previous = l.pinRect.union(l.pinMenuRect)
            for target in row {
                let r = rect(target, in: l)
                #expect(r.size == CGSize(width: 22, height: 22))
                #expect(r.minY == l.tabRect.minY)
                if l.buttonsOnRight {
                    #expect(r.minX == previous.maxX + 4)
                } else {
                    #expect(r.maxX == previous.minX - 4)
                }
                previous = r
                // Takes its press, also on a pinned frame, reveals the frame and has room in the window.
                let mid = CGPoint(x: r.midX, y: r.midY)
                #expect(l.hitTarget(at: mid) == target)
                #expect(l.hitTarget(at: mid, lock: .pinned) == target)
                #expect(l.hitTarget(at: mid, lock: .fixedPosition) == target)
                #expect(l.isInHoverZone(mid))
                #expect(l.windowFrame.contains(r.insetBy(dx: -8, dy: -8)))
            }
            #expect(l.pinMenuRect.maxX <= l.tabRect.minX - 4 || l.pinRect.minX == l.tabRect.maxX + 4)
        }
    }

    @Test func theStudioFrameHasOnlyThePickButton() {
        let capture = CGRect(x: 400, y: 100, width: 200, height: 100)
        let plain = layout(capture, lockButtons: false)
        #expect(plain.rowButtons == [.pickWindow])
        #expect(plain.moreRect.isNull)
        #expect(plain.pickRect == CGRect(x: plain.tabRect.maxX + 4, y: plain.tabRect.minY, width: 22, height: 22))
        for expanded in [false, true] {
            for viewportHandleOn in [false, true] {
                #expect(
                    layout(capture, expanded: expanded, viewportHandleOn: viewportHandleOn, lockButtons: false) == plain
                )
            }
        }
    }

    @Test func theChevronsPlaceTakesNoPressOnceExpandedNorTheCollapsedButtonsPlaces() {
        let capture = CGRect(x: 100, y: 100, width: 200, height: 100)
        let collapsed = layout(capture)
        let all = layout(capture, expanded: true)
        // "»" stands where the viewport button goes; once expanded, the viewport button takes its press.
        #expect(collapsed.moreRect == all.viewportRect)
        let chevron = CGPoint(x: collapsed.moreRect.midX, y: collapsed.moreRect.midY)
        #expect(all.hitTarget(at: chevron) == .viewportButton)
        // Where the raise and pick buttons go: nothing while collapsed, not even hover.
        for r in [all.raiseRect, all.pickRect] {
            let mid = CGPoint(x: r.midX, y: r.midY)
            #expect(collapsed.hitTarget(at: mid) == nil)
            #expect(collapsed.hitTarget(at: mid, lock: .pinned) == nil)
            #expect(!collapsed.isInHoverZone(mid))
        }
    }

    @Test func withTheViewportModeOnTheChevronFollowsTheViewportButton() {
        let capture = CGRect(x: 100, y: 100, width: 200, height: 100)
        let l = layout(capture, viewportHandleOn: true)
        let all = layout(capture, expanded: true)
        #expect(l.viewportRect == all.viewportRect)
        #expect(l.moreRect == all.raiseRect)
        #expect(l.hitTarget(at: CGPoint(x: l.viewportRect.midX, y: l.viewportRect.midY)) == .viewportButton)
        #expect(l.hitTarget(at: CGPoint(x: l.moreRect.midX, y: l.moreRect.midY)) == .moreButtons)
    }

    @Test func theWindowMakesRoomOnlyForTheButtonsShown() {
        // The row reaches past the frame's 40 pt padding on the right (the frame ends at 340); no
        // position box here, which would reach 370.
        let window = { (expanded: Bool, viewportHandleOn: Bool) in
            OverlayLayout(
                captureRect: CGRect(x: 100, y: 100, width: 200, height: 100), screenFrame: screen, tabWidth: 180,
                labelWidth: 60, buttonsExpanded: expanded, viewportHandleOn: viewportHandleOn
            ).windowFrame.maxX
        }
        #expect(window(false, false) == CGFloat(333 + 22 + 8))
        #expect(window(false, true) == CGFloat(359 + 22 + 8))
        #expect(window(true, false) == CGFloat(385 + 22 + 8))
        #expect(window(true, true) == CGFloat(385 + 22 + 8))
    }

    @Test func expandingChangesNothingButTheRowAndWhatMakesRoomForIt() {
        let capture = CGRect(x: 100, y: 100, width: 200, height: 100)
        let collapsed = layout(capture)
        let all = layout(capture, expanded: true)
        #expect(collapsed.tabRect == all.tabRect)
        #expect(collapsed.pinRect == all.pinRect)
        #expect(collapsed.pinMenuRect == all.pinMenuRect)
        #expect(collapsed.labelRect == all.labelRect)
        #expect(collapsed.positionRect == all.positionRect)
        #expect(collapsed.buttonsOnRight == all.buttonsOnRight)
    }

    // The side is decided on the expanded row (pin with ▾, then three buttons: 117 pt past the tab),
    // so expanding never flips it: the tab ending at 1317 leaves it exactly room on a 1440 pt screen
    // with its 6 pt margin, at 1318 the row goes left, collapsed too, though "»" alone would fit.
    @Test(arguments: [(CGFloat(1177), true), (1178, false), (1250, false)])
    func theRowFlipsOnTheExpandedWidth(captureX: CGFloat, onRight: Bool) {
        let capture = CGRect(x: captureX, y: 100, width: 100, height: 100)
        for expanded in [false, true] {
            for viewportHandleOn in [false, true] {
                let l = layout(capture, expanded: expanded, viewportHandleOn: viewportHandleOn)
                #expect(l.buttonsOnRight == onRight)
                if onRight {
                    #expect(l.pinRect.minX == l.tabRect.maxX + 4)
                } else {
                    #expect(l.pinMenuRect.maxX == l.tabRect.minX - 4)
                }
                let far = rect(l.rowButtons.last!, in: l)
                #expect(far.minX >= 6 && far.maxX <= 1440 - 6)
            }
        }
    }

    // The second click of a double click on "»" lands on the button expanding put there.
    @Test(arguments: [OverlayHitTarget.viewportButton, .moreButtons, .raiseViewer, .pickWindow])
    func aRowButtonTakesOnlyASingleClick(target: OverlayHitTarget) {
        #expect(target.takesPress(clickCount: 1))
        #expect(!target.takesPress(clickCount: 2))
        #expect(!target.takesPress(clickCount: 3))
    }

    @Test(arguments: [
        OverlayHitTarget.pin, .pinMenu, .move, .resize(.topLeft), .resize(.bottom), .viewportHandle,
    ])
    func everythingElseTakesAnyClick(target: OverlayHitTarget) {
        for count in 1...3 { #expect(target.takesPress(clickCount: count)) }
    }

    @Test func expandingPutsAButtonUnderTheSecondClick() {
        // Why the row buttons ignore a double click: after "»" the button under the pointer changes.
        let capture = CGRect(x: 100, y: 100, width: 200, height: 100)
        for viewportHandleOn in [false, true] {
            let collapsed = layout(capture, viewportHandleOn: viewportHandleOn)
            let all = layout(capture, expanded: true, viewportHandleOn: viewportHandleOn)
            let chevron = CGPoint(x: collapsed.moreRect.midX, y: collapsed.moreRect.midY)
            let under = all.hitTarget(at: chevron)
            #expect(under == (viewportHandleOn ? .raiseViewer : .viewportButton))
            #expect(under?.takesPress(clickCount: 2) == false)
        }
    }

    @Test func onADisplayAtNegativeCoordinatesTheRowFlipsAtItsRightEdge() {
        // The display's right edge is x 0: the tab ends at -35, 117 pt short of room.
        let capture = CGRect(x: -200, y: -100, width: 150, height: 100)
        let collapsed = layout(capture, on: Self.display)
        let all = layout(capture, on: Self.display, expanded: true)
        #expect(!collapsed.buttonsOnRight)
        #expect(collapsed.tabRect == CGRect(x: -215, y: 10, width: 180, height: 22))
        #expect(collapsed.pinRect == CGRect(x: -254, y: 10, width: 22, height: 22))
        #expect(collapsed.moreRect == CGRect(x: -280, y: 10, width: 22, height: 22))
        #expect(all.viewportRect == collapsed.moreRect)
        #expect(all.raiseRect == CGRect(x: -306, y: 10, width: 22, height: 22))
        #expect(all.pickRect == CGRect(x: -332, y: 10, width: 22, height: 22))
        #expect(collapsed.hitTarget(at: CGPoint(x: -269, y: 21)) == .moreButtons)
        #expect(all.hitTarget(at: CGPoint(x: -269, y: 21)) == .viewportButton)
        #expect(all.hitTarget(at: CGPoint(x: -321, y: 21), lock: .pinned) == .pickWindow)
        #expect(collapsed.hitTarget(at: CGPoint(x: -321, y: 21)) == nil)
        #expect(collapsed.windowFrame.minX == CGFloat(-288))
        #expect(all.windowFrame.minX == CGFloat(-340))
    }
}

/// Which tab button the pointer is on, and where its name shows: beside the row, away from the
/// frame, over no button, nor the tab, nor the notice.
struct OverlayButtonNameTests {
    private static let display = CGRect(x: -2560, y: -180, width: 2560, height: 1440)
    private static let name = CGSize(width: 80, height: 16)

    private func layout(
        _ capture: CGRect, on screenFrame: CGRect = screen, expanded: Bool = false, viewportHandleOn: Bool = false,
        lockButtons: Bool = true, noticeWidth: CGFloat = 0
    ) -> OverlayLayout {
        OverlayLayout(
            captureRect: capture, screenFrame: screenFrame, tabWidth: 180, labelWidth: 60,
            positionSize: CGSize(width: 50, height: 60), noticeWidth: noticeWidth, lockButtons: lockButtons,
            buttonsExpanded: expanded, viewportHandleOn: viewportHandleOn)
    }

    private func rect(_ target: OverlayHitTarget, in l: OverlayLayout) -> CGRect {
        switch target {
        case .pin: l.pinRect
        case .pinMenu: l.pinMenuRect
        case .viewportButton: l.viewportRect
        case .raiseViewer: l.raiseRect
        case .pickWindow: l.pickRect
        case .moreButtons: l.moreRect
        default: .null
        }
    }

    private static let allButtons: [OverlayHitTarget] = [
        .pin, .pinMenu, .viewportButton, .raiseViewer, .pickWindow, .moreButtons,
    ]

    /// Collapsed and expanded, with the viewport mode off and on, on the Capture Area and the studio's
    /// frame: right of the tab, left of it at the screen's right edge, on a display left of and below
    /// the main one, a half-point frame on a 2× display among them, and with the tab above, below and
    /// inside the frame.
    private func everyLayout() -> [(OverlayLayout, CGRect)] {
        let places: [(CGRect, CGRect)] = [
            (CGRect(x: 100, y: 100, width: 200, height: 100), screen),
            (CGRect(x: 1300, y: 100, width: 134, height: 100), screen),
            (CGRect(x: 100, y: 800, width: 200, height: 95), screen),
            (CGRect(x: 100, y: 0, width: 200, height: 900), screen),
            (CGRect(x: -2000.5, y: 100.5, width: 300, height: 200), Self.display),
            (CGRect(x: -200, y: -100, width: 150, height: 100), Self.display),
        ]
        var layouts: [(OverlayLayout, CGRect)] = []
        for (capture, screenFrame) in places {
            for expanded in [false, true] {
                for viewportHandleOn in [false, true] {
                    for lockButtons in [true, false] {
                        let l = layout(
                            capture, on: screenFrame, expanded: expanded, viewportHandleOn: viewportHandleOn,
                            lockButtons: lockButtons, noticeWidth: 120)
                        layouts.append((l, screenFrame))
                    }
                }
            }
        }
        return layouts
    }

    @Test func eachShownButtonIsFoundAndNothingElse() {
        for (l, _) in everyLayout() {
            for target in Self.allButtons {
                let r = rect(target, in: l)
                guard !r.isNull else { continue }
                #expect(l.button(at: CGPoint(x: r.midX, y: r.midY)) == target)
                // Its edges too: the pin's two halves meet without a gap.
                #expect(l.button(at: CGPoint(x: r.minX, y: r.minY)) == target)
            }
            #expect(l.button(at: CGPoint(x: l.tabRect.midX, y: l.tabRect.midY)) == nil)
            #expect(l.button(at: CGPoint(x: l.captureRect.minX - 3, y: l.captureRect.midY)) == nil)
            #expect(l.button(at: CGPoint(x: l.captureRect.midX, y: l.captureRect.midY)) == nil)
            #expect(l.button(at: CGPoint(x: l.noticeRect.midX, y: l.noticeRect.midY)) == nil)
        }
    }

    @Test func aButtonIsFoundWhateverTheLockAndOverTheViewportHandle() {
        let l = layout(CGRect(x: 100, y: 100, width: 200, height: 100), expanded: true)
        for target in Self.allButtons where target != .moreButtons {
            let r = rect(target, in: l)
            let mid = CGPoint(x: r.midX, y: r.midY)
            #expect(l.button(at: mid) == target)
            for lock in CaptureAreaLock.allCases {
                #expect(l.hitTarget(at: mid, lock: lock, viewportHandle: r) == target)
            }
        }
    }

    @Test func theCollapsedButtonsPlacesAreNoButtons() {
        let capture = CGRect(x: 100, y: 100, width: 200, height: 100)
        let collapsed = layout(capture)
        let all = layout(capture, expanded: true)
        for r in [all.raiseRect, all.pickRect] {
            #expect(collapsed.button(at: CGPoint(x: r.midX, y: r.midY)) == nil)
        }
        // Where "»" was, the viewport button once expanded.
        let chevron = CGPoint(x: collapsed.moreRect.midX, y: collapsed.moreRect.midY)
        #expect(collapsed.button(at: chevron) == .moreButtons)
        #expect(all.button(at: chevron) == .viewportButton)
    }

    @Test func theNameCoversNoButtonNorTheTabNorTheNoticeAndStaysOnScreen() {
        for (l, screenFrame) in everyLayout() {
            let row = Self.allButtons.map { rect($0, in: l) }.filter { !$0.isNull }
            for target in Self.allButtons {
                let r = rect(target, in: l)
                let name = l.buttonNameRect(for: target, size: Self.name, screenFrame: screenFrame)
                guard !r.isNull else {
                    #expect(name == nil)
                    continue
                }
                guard let name else {
                    Issue.record("No name for \(target)")
                    continue
                }
                #expect(name.size == Self.name)
                #expect(!name.intersects(l.tabRect))
                #expect(!name.intersects(l.noticeRect))
                for button in row { #expect(!name.intersects(button)) }
                #expect(name.minX >= screenFrame.minX + 6 && name.maxX <= screenFrame.maxX - 6)
                #expect(name.minY >= screenFrame.minY + 6 && name.maxY <= screenFrame.maxY - 6)
                // Whole points, also for a half-point frame on a 2× display.
                #expect(name.origin.x == name.origin.x.rounded() && name.origin.y == name.origin.y.rounded())
            }
        }
    }

    @Test func aboveTheFrameTheNameShowsAboveTheRowCentredOnTheButton() {
        let l = layout(CGRect(x: 100, y: 100, width: 200, height: 100), expanded: true)
        #expect(l.tabPlacement == .above)
        for target in Self.allButtons where target != .moreButtons {
            let r = rect(target, in: l)
            let name = l.buttonNameRect(for: target, size: Self.name, screenFrame: screen)
            #expect(name?.minY == l.tabRect.maxY + 4)
            #expect(name?.midX == r.midX.rounded())
        }
    }

    @Test func belowTheFrameTheNameShowsBelowTheRow() {
        let l = layout(CGRect(x: 100, y: 800, width: 200, height: 95))
        #expect(l.tabPlacement == .below)
        let name = l.buttonNameRect(for: .pin, size: Self.name, screenFrame: screen)
        #expect(name == CGRect(x: l.pinRect.midX - 40, y: l.tabRect.minY - 4 - 16, width: 80, height: 16))
    }

    @Test func insideTheFrameTheNameShowsBelowTheRowInsideTheArea() {
        let l = layout(CGRect(x: 100, y: 0, width: 200, height: 900))
        #expect(l.tabPlacement == .inside)
        let name = l.buttonNameRect(for: .moreButtons, size: Self.name, screenFrame: screen)
        #expect(name?.maxY == l.tabRect.minY - 4)
        #expect(name.map { $0.minY >= l.captureRect.minY } == true)
    }

    @Test func aboveTheFrameWithoutRoomAboveTheNameShowsBelowTheRow() {
        // The tab fits above (it ends at 882, 12 pt from the top); the name wouldn't.
        let l = layout(CGRect(x: 100, y: 750, width: 200, height: 100))
        #expect(l.tabPlacement == .above)
        let name = l.buttonNameRect(for: .pin, size: Self.name, screenFrame: screen)
        #expect(name?.maxY == l.tabRect.minY - 4)
    }

    @Test func belowTheFrameWithoutRoomBelowTheNameShowsAboveTheRow() {
        // No room above the frame; the tab fits below it, 8 pt from the bottom; the name wouldn't.
        let l = layout(CGRect(x: 100, y: 40, width: 200, height: 850))
        #expect(l.tabPlacement == .below)
        let name = l.buttonNameRect(for: .pin, size: Self.name, screenFrame: screen)
        #expect(name?.minY == l.tabRect.maxY + 4)
    }

    @Test func atTheScreensRightEdgeTheNameStaysOnScreen() {
        // The expanded row ends exactly at the margin (1434) on the right of the tab.
        let l = layout(CGRect(x: 1177, y: 100, width: 100, height: 100), expanded: true)
        #expect(l.buttonsOnRight)
        #expect(l.pickRect.maxX == CGFloat(1434))
        #expect(l.buttonNameRect(for: .pickWindow, size: Self.name, screenFrame: screen)?.maxX == CGFloat(1434))
    }

    @Test func onADisplayAtNegativeCoordinatesTheNameStaysOnIt() {
        // At the display's left edge, a name wider than the room left of the pin's centre.
        let l = layout(CGRect(x: -2558, y: -100, width: 100, height: 100), on: Self.display)
        #expect(l.buttonsOnRight)
        let wide = CGSize(width: 500, height: 16)
        let name = l.buttonNameRect(for: .pin, size: wide, screenFrame: Self.display)
        #expect(name == CGRect(x: -2554, y: l.tabRect.maxY + 4, width: 500, height: 16))
        // Left of the tab at the display's right edge (x 0), the pick button's name centred on it.
        let left = layout(CGRect(x: -200, y: -100, width: 150, height: 100), on: Self.display, expanded: true)
        #expect(!left.buttonsOnRight)
        #expect(
            left.buttonNameRect(for: .pickWindow, size: Self.name, screenFrame: Self.display)
                == CGRect(x: -361, y: 36, width: 80, height: 16))
    }

    @Test func theStudioFrameNamesOnlyItsPickButton() {
        let l = layout(CGRect(x: 400, y: 100, width: 200, height: 100), lockButtons: false)
        #expect(l.button(at: CGPoint(x: l.pickRect.midX, y: l.pickRect.midY)) == .pickWindow)
        #expect(l.buttonNameRect(for: .pickWindow, size: Self.name, screenFrame: screen) != nil)
        for target in [OverlayHitTarget.pin, .pinMenu, .viewportButton, .raiseViewer, .moreButtons] {
            #expect(l.buttonNameRect(for: target, size: Self.name, screenFrame: screen) == nil)
        }
    }

    @Test func handlesTheTabAndTheViewportHandleHaveNoName() {
        let l = layout(CGRect(x: 100, y: 100, width: 200, height: 100))
        for target in [OverlayHitTarget.move, .resize(.topLeft), .viewportHandle] {
            #expect(l.buttonNameRect(for: target, size: Self.name, screenFrame: screen) == nil)
        }
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

/// The margins button in the tab row while the area is fitted to its magnet's window, and the margins
/// panel below the position box while the margins are on.
struct OverlayMarginsLayoutTests {
    private let box = CGSize(width: 84, height: 76)
    private let expandedPanel = CGSize(width: 196, height: 182)
    private let capture = CGRect(x: 100, y: 300, width: 400, height: 300)

    private func layout(
        _ capture: CGRect, expanded: Bool = false, viewportHandleOn: Bool = false, panel: CGSize = .zero,
        inner: CGRect? = nil
    ) -> OverlayLayout {
        OverlayLayout(
            captureRect: capture, screenFrame: screen, tabWidth: 180, labelWidth: 60, positionSize: box,
            buttonsExpanded: expanded, viewportHandleOn: viewportHandleOn, marginsButton: true, innerRect: inner,
            marginsPanelSize: panel, marginsPanelWidestWidth: expandedPanel.width)
    }

    @Test(arguments: [
        (false, false, [OverlayHitTarget.marginsButton, .moreButtons]),
        (false, true, [.marginsButton, .viewportButton, .moreButtons]),
        (true, false, [.marginsButton, .viewportButton, .raiseViewer, .pickWindow]),
    ])
    func theMarginsButtonComesRightAfterThePinsMenu(
        expanded: Bool, viewportHandleOn: Bool, row: [OverlayHitTarget]
    ) {
        let l = layout(capture, expanded: expanded, viewportHandleOn: viewportHandleOn)
        #expect(l.rowButtons == row)
        #expect(l.marginsButtonRect.minX == l.pinMenuRect.maxX + 4)
        #expect(l.marginsButtonRect.size == CGSize(width: 22, height: 22))
        let mid = CGPoint(x: l.marginsButtonRect.midX, y: l.marginsButtonRect.midY)
        #expect(l.hitTarget(at: mid, lock: .magnet, fitted: true) == .marginsButton)
        #expect(l.button(at: mid) == .marginsButton)
        #expect(l.isInHoverZone(mid))
        #expect(l.windowFrame.contains(l.marginsButtonRect))
    }

    @Test func withoutTheMarginsButtonTheRowIsAsBefore() {
        let plain = OverlayLayout(
            captureRect: capture, screenFrame: screen, tabWidth: 180, labelWidth: 60, positionSize: box)
        #expect(plain.marginsButtonRect.isNull)
        #expect(plain.marginsPanelRect.isNull)
        #expect(plain.innerRect == capture)
        #expect(plain.rowButtons == [.moreButtons])
    }

    @Test func theStudioFrameHasNoMarginsButton() {
        let l = OverlayLayout(
            captureRect: capture, screenFrame: screen, tabWidth: 180, labelWidth: 60, lockButtons: false,
            marginsButton: true)
        #expect(l.rowButtons == [.pickWindow])
        #expect(l.marginsButtonRect.isNull)
    }

    @Test func thePanelSitsBelowTheBoxOnItsEdgeNextToTheFrame() {
        let collapsed = layout(capture, panel: box)
        // Right of the frame, the column's top level with the frame's top (600).
        #expect(collapsed.positionRect == CGRect(x: 512, y: 524, width: 84, height: 76))
        #expect(collapsed.marginsPanelRect == CGRect(x: 512, y: 444, width: 84, height: 76))
        let expanded = layout(capture, panel: expandedPanel)
        #expect(expanded.positionRect == collapsed.positionRect)
        #expect(expanded.marginsPanelRect == CGRect(x: 512, y: 338, width: 196, height: 182))
        for l in [collapsed, expanded] {
            #expect(l.windowFrame.contains(l.marginsPanelRect))
            #expect(l.isInHoverZone(CGPoint(x: l.marginsPanelRect.midX, y: l.marginsPanelRect.midY)))
        }
    }

    @Test func leftOfTheFrameThePanelKeepsToTheBoxsRightEdge() {
        // The expanded panel wouldn't fit right of the frame, so the column goes left, collapsed too:
        // expanding never moves the box.
        let right = CGRect(x: 1000, y: 300, width: 250, height: 300)
        let collapsed = layout(right, panel: box)
        let expanded = layout(right, panel: expandedPanel)
        #expect(collapsed.positionRect.maxX == CGFloat(1000 - 12))
        #expect(collapsed.marginsPanelRect.maxX == CGFloat(1000 - 12))
        #expect(expanded.positionRect == collapsed.positionRect)
        #expect(expanded.marginsPanelRect.maxX == CGFloat(1000 - 12))
        #expect(expanded.marginsPanelRect.width == 196)
    }

    @Test func theColumnStaysOnScreenBelowAFrameNearTheBottom() {
        let low = CGRect(x: 100, y: 10, width: 400, height: 150)
        let l = layout(low, panel: expandedPanel)
        #expect(l.marginsPanelRect.minY == 6)
        #expect(l.positionRect.minY == l.marginsPanelRect.maxY + 4)
    }

    @Test func theColumnAvoidsARectAtNegativeCoordinates() {
        // On a display left of the main one, with a rect to avoid right of the frame: the box and the
        // panel go left of the frame, clear of it, the panel on the box's right edge.
        let display = CGRect(x: -2560, y: -180, width: 2560, height: 1440)
        let frame = CGRect(x: -1500, y: 200, width: 400, height: 300)
        let avoided = CGRect(x: -1090, y: 100, width: 300, height: 500)
        let l = OverlayLayout(
            captureRect: frame, screenFrame: display, tabWidth: 180, labelWidth: 60, positionSize: box,
            positionAvoiding: avoided, marginsButton: true, marginsPanelSize: expandedPanel,
            marginsPanelWidestWidth: expandedPanel.width)
        #expect(l.positionRect.maxX == frame.minX - 12)
        #expect(l.marginsPanelRect.maxX == frame.minX - 12)
        #expect(l.positionRect.maxY == frame.maxY)
        #expect(l.marginsPanelRect.maxY == l.positionRect.minY - 4)
        #expect(!l.positionRect.intersects(avoided))
        #expect(!l.marginsPanelRect.intersects(avoided))
    }

    @Test func theViewportHandleStaysInsideTheInnerRect() throws {
        // The part fills the inner rect's top: the pill goes below it, inside the inner rect, not in
        // the band above it.
        let inner = CGRect(x: 150, y: 350, width: 300, height: 200)
        let l = layout(capture, inner: inner)
        let part = CGRect(x: 200, y: 450, width: 100, height: 100)
        let handle = try #require(l.viewportHandleRect(for: part))
        #expect(inner.contains(handle))
        #expect(handle.maxY == part.minY - 2)
    }
}
