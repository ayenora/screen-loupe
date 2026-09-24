import CoreGraphics
import Testing

struct CornerRulerTests {
    /// Zoom 8, the image's top-left at the viewport origin: source pixel n spans drawable 8n…8n+8.
    private let state = ZoomPanState(
        zoom: 8, offset: .zero, contentSize: CGSize(width: 200, height: 100),
        viewportSize: CGSize(width: 800, height: 600))
    /// 32 pt on a 2× Viewer.
    private let minimum: CGFloat = 64

    @Test func snapsToWholeSourcePixels() {
        let ruler = CornerRuler(anchor: .viewer(corner: CGPoint(x: 83, y: 45), arms: CGSize(width: 101, height: -99)))
        let placed = ruler.placement(in: state, minimum: minimum)
        #expect(placed.corner == CGPoint(x: 10, y: 6))
        #expect(placed.arms == CGSize(width: 13, height: -12))
    }

    @Test func aViewerRulerStaysPutWhileTheImagePans() {
        let ruler = CornerRuler(anchor: .viewer(corner: CGPoint(x: 80, y: 80), arms: CGSize(width: 160, height: 160)))
        var panned = state
        panned.offset = CGPoint(x: -16, y: 0)
        // The same spot of the Viewer is now two source pixels further right.
        #expect(ruler.placement(in: panned, minimum: minimum).corner == CGPoint(x: 12, y: 10))
    }

    @Test func aPinnedRulerMovesWithTheImage() {
        let ruler = CornerRuler(anchor: .image(corner: CGPoint(x: 10, y: 10), arms: CGSize(width: 20, height: 20)))
        var panned = state
        panned.offset = CGPoint(x: -16, y: 0)
        #expect(ruler.placement(in: panned, minimum: minimum).corner == CGPoint(x: 10, y: 10))
    }

    @Test func zoomingOutLengthensAPinnedRulerButKeepsItsSetLength() {
        let ruler = CornerRuler(anchor: .image(corner: CGPoint(x: 10, y: 10), arms: CGSize(width: 10, height: -10)))
        var out = state
        out.zoom = 2
        // 64 drawable pixels at zoom 2 are 32 source pixels.
        #expect(ruler.placement(in: out, minimum: minimum).arms == CGSize(width: 32, height: -32))
        #expect(ruler.placement(in: state, minimum: minimum).arms == CGSize(width: 10, height: -10))
    }

    @Test func stretchingAnArmSetsItsLength() {
        var ruler = CornerRuler(anchor: .image(corner: CGPoint(x: 10, y: 10), arms: CGSize(width: 10, height: 10)))
        ruler.setEnd(of: .horizontal, to: CGPoint(x: 8 * 35 + 3, y: 0), in: state, minimum: minimum)
        #expect(ruler.anchor == .image(corner: CGPoint(x: 10, y: 10), arms: CGSize(width: 25, height: 10)))
    }

    @Test func anArmFlipsOnlyAFullShortestArmPastTheCorner() {
        var ruler = CornerRuler(anchor: .image(corner: CGPoint(x: 20, y: 20), arms: CGSize(width: 10, height: 10)))
        // Shortest arm at zoom 8: 8 source pixels. Four pixels left of the corner: not yet.
        ruler.setEnd(of: .horizontal, to: CGPoint(x: 8 * 16, y: 0), in: state, minimum: minimum)
        #expect(ruler.placement(in: state, minimum: minimum).arms.width == 8)
        ruler.setEnd(of: .horizontal, to: CGPoint(x: 8 * 9, y: 0), in: state, minimum: minimum)
        #expect(ruler.placement(in: state, minimum: minimum).arms.width == -11)
    }

    @Test func aPinnedRulerDoesNotMove() {
        var ruler = CornerRuler(anchor: .image(corner: CGPoint(x: 10, y: 10), arms: CGSize(width: 10, height: 10)))
        let before = ruler
        ruler.move(by: CGPoint(x: 40, y: 40))
        ruler.setCorner(to: .zero, in: state, minimum: minimum)
        #expect(ruler == before)
    }

    @Test func draggingTheCornerKeepsTheArmEnds() {
        var ruler = CornerRuler(anchor: .viewer(corner: CGPoint(x: 80, y: 80), arms: CGSize(width: 160, height: 160)))
        ruler.setCorner(to: CGPoint(x: 40, y: 120), in: state, minimum: minimum)
        let placed = ruler.placement(in: state, minimum: minimum)
        #expect(placed.corner == CGPoint(x: 5, y: 15))
        #expect(placed.corner.x + placed.arms.width == 30)
        #expect(placed.corner.y + placed.arms.height == 30)
    }

    @Test func theCornerStopsAShortestArmFromAnEnd() {
        var ruler = CornerRuler(anchor: .viewer(corner: CGPoint(x: 80, y: 80), arms: CGSize(width: 160, height: 160)))
        ruler.setCorner(to: CGPoint(x: 400, y: 80), in: state, minimum: minimum)
        #expect(ruler.placement(in: state, minimum: minimum).arms.width == 8)
    }

    @Test func pinningAndUnpinningKeepsWhereItIsDrawn() {
        var ruler = CornerRuler(anchor: .viewer(corner: CGPoint(x: 83, y: 45), arms: CGSize(width: 101, height: -99)))
        let before = ruler.placement(in: state, minimum: minimum)
        ruler.togglePin(in: state, minimum: minimum)
        #expect(ruler.isPinned)
        #expect(ruler.placement(in: state, minimum: minimum) == before)
        ruler.togglePin(in: state, minimum: minimum)
        #expect(!ruler.isPinned)
        #expect(ruler.placement(in: state, minimum: minimum) == before)
    }
}

struct CornerRulerReviewTests {
    private let state = ZoomPanState(
        zoom: 8, offset: .zero, contentSize: CGSize(width: 200, height: 100),
        viewportSize: CGSize(width: 800, height: 600))

    @Test func stretchingOnePinnedArmKeepsTheOthersSetLength() {
        var ruler = CornerRuler(anchor: .image(corner: CGPoint(x: 20, y: 20), arms: CGSize(width: 10, height: 2)))
        var out = state
        out.zoom = 2
        // Zoomed out, the vertical arm looks 32 px long; stretching the horizontal one keeps its 2.
        ruler.setEnd(of: .horizontal, to: CGPoint(x: 2 * 70, y: 0), in: out, minimum: 64)
        #expect(ruler.anchor == .image(corner: CGPoint(x: 20, y: 20), arms: CGSize(width: 50, height: 2)))
    }

    @Test func aViewerRulerBeyondTheViewportComesBackInside() {
        let ruler = CornerRuler(anchor: .viewer(corner: CGPoint(x: 1600, y: 900), arms: CGSize(width: 80, height: 80)))
        let placed = ruler.placement(in: state, minimum: 64)
        #expect(placed.corner == CGPoint(x: 100, y: 75))
    }
}
