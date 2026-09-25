import CoreGraphics
import Testing

/// A window at x 100...500, y 100...400.
private let window = CGRect(x: 100, y: 100, width: 400, height: 300)

struct EdgeSnappingTests {
    @Test func leftEdgeSnapsToTheWindowsLeftEdgeWithinReach() {
        let rect = CGRect(x: 106, y: 150, width: 200, height: 100)
        let snapped = EdgeSnapping.resized(rect, handle: .left, targets: [window])
        #expect(snapped == CGRect(x: 100, y: 150, width: 206, height: 100))
    }

    @Test func edgeFartherThanReachStaysPut() {
        let rect = CGRect(x: 109, y: 150, width: 200, height: 100)
        #expect(EdgeSnapping.resized(rect, handle: .left, targets: [window]) == rect)
    }

    @Test func onlyTheEdgesTheHandleMovesSnap() {
        // The right edge is 3 pt from the window's right edge, but the left handle is dragged.
        let rect = CGRect(x: 150, y: 150, width: 347, height: 100)
        #expect(EdgeSnapping.resized(rect, handle: .left, targets: [window]) == rect)
    }

    @Test func cornerSnapsBothItsEdges() {
        let rect = CGRect(x: 200, y: 150, width: 296, height: 254)
        let snapped = EdgeSnapping.resized(rect, handle: .topRight, targets: [window])
        #expect(snapped == CGRect(x: 200, y: 150, width: 300, height: 250))
    }

    @Test func edgeSnapsToTheOutsideOfAWindowToo() {
        // The area's left edge right of the window, 4 pt from its right edge.
        let rect = CGRect(x: 504, y: 150, width: 200, height: 100)
        #expect(EdgeSnapping.resized(rect, handle: .left, targets: [window]).minX == 500)
    }

    @Test func windowNotBesideTheEdgeIsIgnored() {
        // Level with the window's left edge in x, but entirely above it.
        let rect = CGRect(x: 104, y: 500, width: 200, height: 100)
        #expect(EdgeSnapping.resized(rect, handle: .left, targets: [window]) == rect)
    }

    @Test func nearestOfSeveralEdgesWins() {
        let other = CGRect(x: 110, y: 0, width: 50, height: 1000)
        let rect = CGRect(x: 107, y: 150, width: 200, height: 100)
        #expect(EdgeSnapping.resized(rect, handle: .left, targets: [window, other]).minX == 110)
    }

    @Test func snapBelowTheMinimumSizeIsSkipped() {
        // Snapping the right edge to 500 would leave 60 pt, under the 64 pt minimum.
        let rect = CGRect(x: 440, y: 150, width: 66, height: 100)
        #expect(EdgeSnapping.resized(rect, handle: .right, targets: [window]) == rect)
    }

    @Test func moveSnapsTheClosestEdgeAndKeepsTheSize() {
        // Left edge 5 pt from 100, right edge 7 pt from 500: the left one wins.
        let rect = CGRect(x: 105, y: 150, width: 388, height: 100)
        #expect(EdgeSnapping.moved(rect, targets: [window]) == CGRect(x: 100, y: 150, width: 388, height: 100))
    }

    @Test func moveSnapsEachAxisOnItsOwn() {
        let rect = CGRect(x: 297, y: 102, width: 200, height: 100)
        #expect(EdgeSnapping.moved(rect, targets: [window]) == CGRect(x: 300, y: 100, width: 200, height: 100))
    }

    @Test func moveWithNothingInReachStaysPut() {
        let rect = CGRect(x: 200, y: 200, width: 100, height: 100)
        #expect(EdgeSnapping.moved(rect, targets: [window]) == rect)
    }

    @Test func pickTakesTheFrontmostWindowUnderThePoint() {
        let front = CGRect(x: 300, y: 300, width: 400, height: 400)
        let point = CGPoint(x: 350, y: 350)
        #expect(EdgeSnapping.window(at: point, in: [front, window]) == front)
        #expect(EdgeSnapping.window(at: CGPoint(x: 150, y: 150), in: [front, window]) == window)
        #expect(EdgeSnapping.window(at: CGPoint(x: 900, y: 900), in: [front, window]) == nil)
    }
}
