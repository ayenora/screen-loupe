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
