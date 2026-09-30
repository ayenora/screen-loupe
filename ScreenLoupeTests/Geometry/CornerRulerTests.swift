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

    @Test func whileTheImageMovesAViewerRulerIsDrawnOffTheGridWhereItWasSet() {
        let ruler = CornerRuler(anchor: .viewer(corner: CGPoint(x: 83, y: 45), arms: CGSize(width: 101, height: -99)))
        let free = ruler.freePlacement(in: state, minimum: minimum)
        #expect(free?.corner == CGPoint(x: 83, y: 45))
        #expect(free?.arms == CGSize(width: 101, height: -99))
        var panned = state
        panned.offset = CGPoint(x: -21, y: 5)
        #expect(ruler.freePlacement(in: panned, minimum: minimum)?.corner == CGPoint(x: 83, y: 45))
    }

    @Test func placedWhereItShowsTheFreeRulerStartsExactlyOnItsPixels() {
        var ruler = CornerRuler(anchor: .viewer(corner: CGPoint(x: 83, y: 45), arms: CGSize(width: 101, height: -99)))
        let placed = ruler.placement(in: state, minimum: minimum)
        let corner = state.viewportPoint(forSourcePoint: placed.corner)
        let arms = CGSize(width: placed.arms.width * state.zoom, height: placed.arms.height * state.zoom)
        ruler.place(corner: corner, arms: arms)
        let free = ruler.freePlacement(in: state, minimum: minimum)
        #expect(free?.corner == corner)
        #expect(free?.arms == arms)
        #expect(ruler.placement(in: state, minimum: minimum) == placed)
    }

    @Test func aFreeArmIsNeverShorterThanTheMinimum() {
        let ruler = CornerRuler(anchor: .viewer(corner: CGPoint(x: 80, y: 80), arms: CGSize(width: 10, height: -3)))
        // The shortest arm is 8 source pixels at zoom 8: 64 drawable pixels.
        #expect(ruler.freePlacement(in: state, minimum: minimum)?.arms == CGSize(width: 64, height: -64))
    }

    @Test func aPinnedRulerHasNoFreePlacement() {
        var ruler = CornerRuler(anchor: .image(corner: CGPoint(x: 10, y: 10), arms: CGSize(width: 20, height: 20)))
        #expect(ruler.freePlacement(in: state, minimum: minimum) == nil)
        ruler.place(corner: .zero, arms: CGSize(width: 64, height: 64))
        #expect(ruler.anchor == .image(corner: CGPoint(x: 10, y: 10), arms: CGSize(width: 20, height: 20)))
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

    @Test func aPinnedRulerStaysOnItsPixelsWhenTheAreasLeftOrTopEdgeIsDragged() {
        // The left edge dragged 3 px right and the top edge 2 px down: the image's pixels stay on
        // screen, now counted from the new corner.
        let shift = CGPoint(x: 3, y: 2)
        var after = state
        after.contentSize = CGSize(width: 197, height: 98)
        after.offset = CGPoint(x: shift.x * state.zoom, y: shift.y * state.zoom)
        var pinned = CornerRuler(anchor: .image(corner: CGPoint(x: 10, y: 6), arms: CGSize(width: 12, height: -9)))
        pinned.followAreaOrigin(shift: shift)
        let placed = pinned.placement(in: after, minimum: minimum)
        #expect(placed.corner == CGPoint(x: 7, y: 4))
        #expect(placed.arms == CGSize(width: 12, height: -9))
        #expect(
            after.viewportPoint(forSourcePoint: placed.corner)
                == state.viewportPoint(forSourcePoint: CGPoint(x: 10, y: 6)))

        let fixed = CornerRuler(anchor: .viewer(corner: CGPoint(x: 80, y: 80), arms: CGSize(width: 160, height: 160)))
        var moved = fixed
        moved.followAreaOrigin(shift: shift)
        #expect(moved == fixed)
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

/// A pinned ruler is kept in Capture Area pixels and shown over the picture through `PictureInArea`,
/// as the reference layers are: over a snapshot of part of the area it stays on the same pixels.
struct CornerRulerOverPictureTests {
    private let state = ZoomPanState(
        zoom: 8, offset: .zero, contentSize: CGSize(width: 60, height: 40),
        viewportSize: CGSize(width: 800, height: 600))
    /// A snapshot of the area's part from 30, 20.
    private let pictureOrigin = CGPoint(x: 30, y: 20)

    @Test func overASnapshotAPinnedRulerSitsOnTheAreaPixelsItWasPinnedTo() {
        let ruler = CornerRuler(anchor: .image(corner: CGPoint(x: 40, y: 25), arms: CGSize(width: 12, height: -9)))
        let placed = ruler.placement(in: state, minimum: 64, pictureOrigin: pictureOrigin)
        #expect(placed.corner == CGPoint(x: 10, y: 5))
        #expect(placed.arms == CGSize(width: 12, height: -9))
        // Over the live view the same ruler is where it was pinned.
        #expect(ruler.placement(in: state, minimum: 64).corner == CGPoint(x: 40, y: 25))
    }

    @Test func aPinnedRulerLeftOfOrAboveTheSnapshotLiesOutsideIt() {
        let ruler = CornerRuler(anchor: .image(corner: CGPoint(x: 5, y: 2), arms: CGSize(width: 10, height: 10)))
        #expect(ruler.placement(in: state, minimum: 64, pictureOrigin: pictureOrigin).corner == CGPoint(x: -25, y: -18))
    }

    @Test func pinningOverASnapshotKeepsTheAreaPixelsUnderIt() {
        // Drawn at the snapshot's pixel 10, 6: the area's 40, 26.
        var ruler = CornerRuler(anchor: .viewer(corner: CGPoint(x: 83, y: 51), arms: CGSize(width: 101, height: -99)))
        let before = ruler.placement(in: state, minimum: 64, pictureOrigin: pictureOrigin)
        ruler.togglePin(in: state, minimum: 64, pictureOrigin: pictureOrigin)
        #expect(ruler.anchor == .image(corner: CGPoint(x: 40, y: 26), arms: CGSize(width: 13, height: -12)))
        #expect(ruler.placement(in: state, minimum: 64, pictureOrigin: pictureOrigin) == before)
        // Back on the live view it is on the same area pixels.
        #expect(ruler.placement(in: state, minimum: 64).corner == CGPoint(x: 40, y: 26))
        ruler.togglePin(in: state, minimum: 64, pictureOrigin: pictureOrigin)
        #expect(!ruler.isPinned)
        #expect(ruler.placement(in: state, minimum: 64, pictureOrigin: pictureOrigin) == before)
    }

    @Test func stretchingAnArmOverASnapshotMeasuresFromTheCornerShown() {
        var ruler = CornerRuler(anchor: .image(corner: CGPoint(x: 40, y: 25), arms: CGSize(width: 10, height: 10)))
        // The corner shows at the snapshot's pixel 10; the end dragged to its pixel 35.
        ruler.setEnd(
            of: .horizontal, to: CGPoint(x: 8 * 35 + 3, y: 0), in: state, minimum: 64, pictureOrigin: pictureOrigin)
        #expect(ruler.anchor == .image(corner: CGPoint(x: 40, y: 25), arms: CGSize(width: 25, height: 10)))
        ruler.setEnd(of: .vertical, to: CGPoint(x: 0, y: 8 * 20), in: state, minimum: 64, pictureOrigin: pictureOrigin)
        #expect(ruler.anchor == .image(corner: CGPoint(x: 40, y: 25), arms: CGSize(width: 25, height: 15)))
    }

    @Test func overASnapshotAPinnedRulerFollowsTheAreasCornerAsTheSnapshotDoes() {
        // The area's left edge dragged 3 px right, its top 2 px down: the snapshot's place in the
        // area and the ruler's corner both move back by as much, so it shows on the same pixels.
        let shift = CGPoint(x: 3, y: 2)
        var ruler = CornerRuler(anchor: .image(corner: CGPoint(x: 40, y: 25), arms: CGSize(width: 12, height: 9)))
        ruler.followAreaOrigin(shift: shift)
        let movedOrigin = RecentCaptureRules.areaOrigin(pictureOrigin, isFile: false, followingShift: shift)
        #expect(ruler.placement(in: state, minimum: 64, pictureOrigin: movedOrigin).corner == CGPoint(x: 10, y: 5))
    }

    @Test func picturePointUndoesAreaPoint() {
        let point = CGPoint(x: 7, y: -3)
        #expect(PictureInArea.picturePoint(point, pictureOrigin: pictureOrigin) == CGPoint(x: -23, y: -23))
        #expect(
            PictureInArea.areaPoint(
                PictureInArea.picturePoint(point, pictureOrigin: pictureOrigin), pictureOrigin: pictureOrigin)
                == point)
    }
}
