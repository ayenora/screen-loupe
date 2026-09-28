import CoreGraphics
import Testing

struct SidePanelEdgeTests {
    /// The narrowest column, 250 pt, in a Viewer 600 pt tall.
    private let bounds = CGRect(x: 0, y: 0, width: 250, height: 600)

    private func grabs(_ x: CGFloat, _ y: CGFloat, _ b: CGRect? = nil) -> Bool {
        SidePanelEdge.grabs(CGPoint(x: x, y: y), in: b ?? bounds)
    }

    @Test func theStripIsFivePointsAlongTheLeftEdgeAndFullHeight() {
        #expect(SidePanelEdge.grabRect(in: bounds) == CGRect(x: 0, y: 0, width: 5, height: 600))
    }

    @Test func theLeftEdgeGrabsAlongItsWholeHeight() {
        #expect(grabs(0, 0))
        #expect(grabs(0, 300))
        #expect(grabs(4.9, 599.9))
    }

    /// The strip is half-open, as `NSView` hit-testing takes rects: 5 pt in is the panel's.
    @Test func fivePointsInIsThePanels() {
        #expect(!grabs(5, 300))
    }

    /// The reported bug: a press in the middle of a panel resized the column.
    @Test func theMiddleOfThePanelDoesNotGrab() {
        #expect(!grabs(125, 300))
        #expect(!grabs(125, 0))
    }

    @Test func theRightEdgeDoesNotGrab() {
        #expect(!grabs(249.9, 300))
    }

    @Test func outsideTheColumnDoesNotGrab() {
        #expect(!grabs(-0.1, 300))
        #expect(!grabs(2, -0.1))
        #expect(!grabs(2, 600))
    }

    @Test func theWidestColumnKeepsTheSameStrip() {
        let wide = CGRect(x: 0, y: 0, width: 320, height: 600)
        #expect(SidePanelEdge.grabRect(in: wide) == CGRect(x: 0, y: 0, width: 5, height: 600))
        #expect(!grabs(160, 300, wide))
    }

    @Test func theStripFollowsTheBoundsOrigin() {
        let moved = CGRect(x: 10, y: 20, width: 250, height: 600)
        #expect(SidePanelEdge.grabRect(in: moved) == CGRect(x: 10, y: 20, width: 5, height: 600))
        #expect(grabs(12, 300, moved))
        #expect(!grabs(2, 300, moved))
    }

    @Test func aColumnNarrowerThanTheStripIsAllStrip() {
        let thin = CGRect(x: 0, y: 0, width: 3, height: 600)
        #expect(SidePanelEdge.grabRect(in: thin) == thin)
    }

    @Test func anEmptyColumnGrabsNothing() {
        #expect(!grabs(0, 0, .zero))
        #expect(!grabs(0, 0, CGRect(x: 0, y: 0, width: 250, height: 0)))
    }
}
