import CoreGraphics
import Testing

private func window(_ id: CGWindowID, _ frame: CGRect) -> ScreenWindow {
    ScreenWindow(id: id, frame: frame, layer: 0, isOnScreen: true, alpha: 1)
}

/// A window at x 100...500, y 100...400, and one in front of it at x 300...700, y 300...700.
private let back = window(1, CGRect(x: 100, y: 100, width: 400, height: 300))
private let front = window(2, CGRect(x: 300, y: 300, width: 400, height: 400))

struct WindowMagnetTests {
    @Test func pickTakesTheFrontmostWindowUnderThePoint() {
        #expect(WindowMagnet.window(at: CGPoint(x: 350, y: 350), in: [front, back]) == front)
        #expect(WindowMagnet.window(at: CGPoint(x: 150, y: 150), in: [front, back]) == back)
        #expect(WindowMagnet.window(at: CGPoint(x: 900, y: 900), in: [front, back]) == nil)
    }

    @Test func theWindowUnderTheAreaIsTheFrontmostHoldingItsCentre() {
        // Centre (350, 350): both windows hold it, the front one wins.
        #expect(
            WindowMagnet.window(under: CGRect(x: 250, y: 250, width: 200, height: 200), in: [front, back]) == front)
        // Centre (200, 150): only the back one. The front one overlapping a corner doesn't count.
        #expect(WindowMagnet.window(under: CGRect(x: 150, y: 100, width: 100, height: 100), in: [front, back]) == back)
        // Centre (800, 150): none, though the area overlaps the back window.
        #expect(WindowMagnet.window(under: CGRect(x: 450, y: 100, width: 700, height: 100), in: [front, back]) == nil)
    }

    private let area = CGRect(x: 150, y: 200, width: 120, height: 80)

    private func followed(to frame: CGRect) -> CGRect {
        WindowMagnet.area(at: WindowMagnet.placement(of: area, on: back.frame), on: frame)
    }

    @Test func thePlacementIsTheOffsetFromTheTopLeftCornerAndTheSize() {
        // Top-left corners: the area's (150, 280), the window's (100, 400).
        #expect(WindowMagnet.placement(of: area, on: back.frame) == CGRect(x: 50, y: -120, width: 120, height: 80))
        #expect(followed(to: back.frame) == area)
    }

    @Test func aMovedWindowCarriesTheArea() {
        #expect(followed(to: back.frame.offsetBy(dx: 30, dy: -45)) == CGRect(x: 180, y: 155, width: 120, height: 80))
    }

    @Test func aWindowResizedByItsRightOrBottomEdgeLeavesTheArea() {
        // The bottom edge is minY: the top-left corner (100, 400) stays.
        #expect(followed(to: CGRect(x: 100, y: 20, width: 700, height: 380)) == area)
    }

    @Test func aWindowResizedByItsLeftOrTopEdgeCarriesTheAreaWithoutResizingIt() {
        // Left edge 40 pt out, top edge 25 pt up: the top-left corner moves to (60, 425).
        #expect(
            followed(to: CGRect(x: 60, y: 100, width: 440, height: 325))
                == CGRect(x: 110, y: 225, width: 120, height: 80))
    }

    @Test func aMoveOntoADisplayAtNegativeCoordinatesKeepsTheOffset() {
        #expect(
            followed(to: CGRect(x: -1500, y: 600, width: 400, height: 300))
                == CGRect(x: -1450, y: 700, width: 120, height: 80))
    }

    @Test func followingAcrossScalesDoesNotDrift() {
        // A half-point offset on a Retina display; each step the area is snapped to whole points on
        // a 1x display, or to half points on a 2x one, as the controller's apply does.
        func snapped(_ rect: CGRect, scale: CGFloat) -> CGRect {
            CGRect(
                x: (rect.minX * scale).rounded() / scale, y: (rect.minY * scale).rounded() / scale,
                width: rect.width, height: rect.height)
        }
        let retinaArea = CGRect(x: 150.5, y: 200.5, width: 120, height: 80)
        let placement = WindowMagnet.placement(of: retinaArea, on: back.frame)
        var shown = retinaArea
        for step in 1...6 {
            let window = back.frame.offsetBy(dx: CGFloat(step * 7), dy: 0)
            shown = snapped(WindowMagnet.area(at: placement, on: window), scale: step.isMultiple(of: 2) ? 2 : 1)
        }
        // Back where it started, on the Retina display: the half points are still there.
        shown = snapped(WindowMagnet.area(at: placement, on: back.frame), scale: 2)
        #expect(shown == retinaArea)
    }

    @Test func theMagnetHoldsAnOrdinaryWindowOnScreen() {
        #expect(WindowMagnet.holds(back))
    }

    @Test func aClosedWindowDoesNotHold() {
        #expect(!WindowMagnet.holds(nil))
    }

    @Test func aWindowOffScreenDoesNotHold() {
        var hidden = back
        hidden.isOnScreen = false
        #expect(!WindowMagnet.holds(hidden))
    }

    @Test func aWindowThatChangesLayerDoesNotHold() {
        var floating = back
        floating.layer = 3
        #expect(!WindowMagnet.holds(floating))
    }

    @Test func aTransparentOrEmptyWindowDoesNotHold() {
        var transparent = back
        transparent.alpha = 0
        #expect(!WindowMagnet.holds(transparent))
        var empty = back
        empty.frame = CGRect(x: 100, y: 100, width: 0, height: 300)
        #expect(!WindowMagnet.holds(empty))
    }

    @Test func aWindowFillingADisplayStillHolds() {
        // Zoomed with the menu bar and the Dock hidden, or a borderless player: full screen proper
        // changes the Space, which lets go on its own.
        #expect(WindowMagnet.holds(window(1, CGRect(x: 0, y: 0, width: 1440, height: 900))))
    }

    @Test func oneBadReadDoesNotLetGoTwoInARowDo() {
        #expect(!WindowMagnet.letsGo(afterBadReads: 1))
        #expect(WindowMagnet.letsGo(afterBadReads: 2))
    }
}

/// The magnet's area fitted to its window: it takes the window's bounds as the window moves and
/// resizes, and the tab lands it back on them.
struct WindowMagnetFittedTests {
    private let window = CGRect(x: 100, y: 100, width: 400, height: 300)
    private let minimum = CaptureAreaEditing.minimumSize

    // MARK: Fitted

    @Test func anAreaOnTheWindowsBoundsIsFitted() {
        #expect(WindowMagnet.isFitted(window, to: window))
        #expect(WindowMagnet.fitTolerance == 1)
    }

    @Test(arguments: [
        // Each edge on its own, out or in, by the whole tolerance: still fitted.
        (CGRect(x: 99, y: 100, width: 401, height: 300), true),
        (CGRect(x: 101, y: 100, width: 399, height: 300), true),
        (CGRect(x: 100, y: 100, width: 401, height: 300), true),
        (CGRect(x: 100, y: 99, width: 400, height: 301), true),
        (CGRect(x: 100, y: 100, width: 400, height: 301), true),
        // Every edge 1 pt out at once.
        (CGRect(x: 99, y: 99, width: 402, height: 302), true),
        // Half a pixel of a 1× display, a quarter of a point on a 2× one: Fit to Window's pixel snap.
        (CGRect(x: 100.5, y: 99.5, width: 399.5, height: 300.5), true),
        (CGRect(x: 100.25, y: 100, width: 399.75, height: 300.25), true),
        // One pixel of a 2× display past the tolerance, on one edge.
        (CGRect(x: 98.5, y: 100, width: 401.5, height: 300), false),
        (CGRect(x: 100, y: 100, width: 400, height: 301.5), false),
        // Moved 2 pt: the same size, but off every tolerance.
        (CGRect(x: 102, y: 100, width: 400, height: 300), false),
        // Smaller by more than the tolerance on the right, as a minimum-size area on a small window.
        (CGRect(x: 100, y: 100, width: 398, height: 300), false),
    ])
    func fittedWithinOnePointOnEveryEdge(area: CGRect, fitted: Bool) {
        #expect(WindowMagnet.isFitted(area, to: window) == fitted)
    }

    @Test func fittedAtNegativeOrigins() {
        let left = CGRect(x: -1500, y: -200, width: 800, height: 600)
        #expect(WindowMagnet.isFitted(CGRect(x: -1501, y: -199, width: 801, height: 599), to: left))
        #expect(!WindowMagnet.isFitted(CGRect(x: -1502, y: -200, width: 802, height: 600), to: left))
    }

    @Test func theBoundsAreTheWindowsDownToTheMinimumKeepingTheTopLeft() {
        #expect(WindowMagnet.bounds(of: window) == window)
        // 50 wide: 64, from the same left edge. 40 tall: 64, from the same top edge (y 400).
        #expect(
            WindowMagnet.bounds(of: CGRect(x: 100, y: 360, width: 50, height: 40))
                == CGRect(x: 100, y: 336, width: 64, height: 64))
        #expect(
            WindowMagnet.bounds(of: CGRect(x: 100, y: 100, width: 300, height: 40))
                == CGRect(x: 100, y: 76, width: 300, height: 64))
        #expect(
            WindowMagnet.bounds(of: CGRect(x: -900, y: -50, width: 30, height: 200))
                == CGRect(x: -900, y: -50, width: 64, height: 200))
        // Exactly the minimum stays.
        #expect(
            WindowMagnet.bounds(of: CGRect(x: 10, y: 10, width: 64, height: 64))
                == CGRect(x: 10, y: 10, width: 64, height: 64))
    }

    // MARK: Following

    private func follow(_ area: CGRect, from previous: CGRect, to next: CGRect) -> WindowMagnet.Follow {
        WindowMagnet.follow(
            area: area, placement: WindowMagnet.placement(of: area, on: previous), from: previous, to: next)
    }

    @Test(arguments: OverlayHandle.allCases)
    func aFittedAreaFollowsTheWindowResizedFromEachEdgeAndCorner(_ edge: OverlayHandle) {
        let resized = CaptureAreaEditing.resized(window, handle: edge, by: CGVector(dx: 37, dy: -23))
        #expect(resized != window)
        #expect(follow(window, from: window, to: resized) == .fitted(resized))
        let grown = CaptureAreaEditing.resized(window, handle: edge, by: CGVector(dx: -37, dy: 23))
        #expect(follow(window, from: window, to: grown) == .fitted(grown))
    }

    @Test func aFittedAreaFollowsAWindowMovedAndResizedInOnePoll() {
        let next = CGRect(x: -300, y: 450, width: 520, height: 180)
        #expect(follow(window, from: window, to: next) == .fitted(next))
    }

    @Test func aFittedAreaFollowsAMove() {
        let next = window.offsetBy(dx: 12.5, dy: -40)
        #expect(follow(window, from: window, to: next) == .fitted(next))
    }

    @Test func anAreaSnappedWithinTheToleranceStillFollows() {
        // Fit to Window on a 1× display rounded a half-point window out by half a point.
        let previous = CGRect(x: 100.5, y: 100, width: 400, height: 300)
        let area = CGRect(x: 100, y: 100, width: 401, height: 300)
        let next = CGRect(x: 100.5, y: 100, width: 450, height: 300)
        #expect(follow(area, from: previous, to: next) == .fitted(next))
    }

    @Test func anAreaOffTheBoundsKeepsItsPlaceAndSize() {
        let area = CGRect(x: 150, y: 200, width: 120, height: 80)
        let next = CGRect(x: 60, y: 100, width: 700, height: 325)
        // The top-left corner moved from (100, 400) to (60, 425).
        #expect(follow(area, from: window, to: next) == .moved(CGRect(x: 110, y: 225, width: 120, height: 80)))
        // One edge 1.5 pt off the window's: not fitted, so it only moves.
        let almost = CGRect(x: 100, y: 100, width: 401.5, height: 300)
        #expect(follow(almost, from: window, to: next) == .moved(CGRect(x: 60, y: 125, width: 401.5, height: 300)))
    }

    @Test func aWindowBelowTheMinimumLeavesTheAreaAtTheMinimumNoLongerFitted() {
        let small = CGRect(x: 100, y: 360, width: 50, height: 40)
        let step = follow(window, from: window, to: small)
        let atMinimum = CGRect(x: 100, y: 336, width: 64, height: 64)
        #expect(step == .fitted(atMinimum))
        #expect(!WindowMagnet.isFitted(atMinimum, to: small))
        // The window grows again: the area only moves with its top-left corner.
        let placement = WindowMagnet.placement(of: atMinimum, on: small)
        let grown = CGRect(x: 80, y: 100, width: 400, height: 300)
        #expect(
            WindowMagnet.follow(area: atMinimum, placement: placement, from: small, to: grown)
                == .moved(CGRect(x: 80, y: 336, width: 64, height: 64)))
    }

    @Test func aWindowShrinkingToExactlyTheMinimumKeepsTheAreaFitted() {
        let smallest = CGRect(x: 100, y: 336, width: 64, height: 64)
        #expect(follow(window, from: window, to: smallest) == .fitted(smallest))
        #expect(WindowMagnet.isFitted(smallest, to: smallest))
    }

    @Test func followingTheBoundsOntoANegativeDisplay() {
        let next = CGRect(x: -1500, y: -300, width: 640, height: 480)
        #expect(follow(window, from: window, to: next) == .fitted(next))
    }

    // MARK: Snapping back with the tab

    @Test func theSnapReachIsTheCommandSnaps() {
        #expect(EdgeSnapping.reach == 8)
    }

    @Test(arguments: [
        // Right on it, or off by the whole reach one way or both: lands on it.
        (CGPoint(x: 0, y: 0), true),
        (CGPoint(x: 8, y: 0), true),
        (CGPoint(x: -8, y: 0), true),
        (CGPoint(x: 0, y: 8), true),
        (CGPoint(x: -8, y: -8), true),
        (CGPoint(x: 3.5, y: -7.25), true),
        // One pixel over the reach: of a 2× display, of a 1× one.
        (CGPoint(x: 8.5, y: 0), false),
        (CGPoint(x: 0, y: -8.5), false),
        (CGPoint(x: 9, y: 0), false),
        (CGPoint(x: -20, y: 0), false),
    ])
    func theTabLandsTheAreaOnTheWindowWithinTheReach(offset: CGPoint, snaps: Bool) {
        let area = window.offsetBy(dx: offset.x, dy: offset.y)
        #expect(WindowMagnet.snappedOnto(window, area: area) == (snaps ? window : nil))
    }

    @Test(arguments: [
        // Up to the tolerance larger or smaller: lands on it, at the window's size.
        (CGSize(width: 401, height: 300), true),
        (CGSize(width: 399, height: 301), true),
        (CGSize(width: 400.5, height: 299.5), true),
        // One pixel of a 2× display past it, or far off.
        (CGSize(width: 401.5, height: 300), false),
        (CGSize(width: 400, height: 298.5), false),
        (CGSize(width: 390, height: 300), false),
    ])
    func onlyAnAreaOfTheWindowsSizeLandsOnIt(size: CGSize, snaps: Bool) {
        let area = CGRect(origin: CGPoint(x: 102, y: 97), size: size)
        #expect(WindowMagnet.snappedOnto(window, area: area) == (snaps ? window : nil))
    }

    @Test func aWindowBelowTheMinimumTakesNoSnap() {
        // A minimum-size area over a 63 × 300 window: within the tolerance, but it can't fit.
        let narrow = CGRect(x: 100, y: 100, width: 63, height: 300)
        #expect(WindowMagnet.snappedOnto(narrow, area: CGRect(x: 100, y: 100, width: 64, height: 300)) == nil)
        let smallest = CGRect(x: 100, y: 100, width: 64, height: 64)
        #expect(WindowMagnet.snappedOnto(smallest, area: smallest.offsetBy(dx: 4, dy: 4)) == smallest)
    }

    @Test func snappingAtNegativeOriginsAndFractionalPoints() {
        let left = CGRect(x: -1500.5, y: -200, width: 800, height: 600)
        #expect(WindowMagnet.snappedOnto(left, area: left.offsetBy(dx: 7.5, dy: -8)) == left)
        #expect(WindowMagnet.snappedOnto(left, area: left.offsetBy(dx: 7.5, dy: -8.5)) == nil)
    }
}
