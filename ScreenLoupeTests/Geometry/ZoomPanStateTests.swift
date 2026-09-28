import CoreGraphics
import Testing

struct ZoomPanStateTests {
    @Test(arguments: [CGPoint(x: 100, y: 100), CGPoint(x: 250, y: 120), CGPoint(x: 301, y: 149)])
    func zoomKeepsTheSourcePointUnderTheCursor(anchor: CGPoint) {
        // 200×100 at 2× in a 400×300 viewport; at 4× the image (800×400) is larger than the
        // viewport on both axes, so clamping doesn't move it.
        let start = ZoomPanState(
            zoom: 2, contentSize: CGSize(width: 200, height: 100), viewportSize: CGSize(width: 400, height: 300)
        )
        .centered()
        let before = start.sourcePoint(forViewportPoint: anchor)
        let zoomed = start.zoomed(to: 4, around: anchor)
        let after = zoomed.sourcePoint(forViewportPoint: anchor)
        #expect(zoomed.zoom == 4)
        #expect(abs(after.x - before.x) <= 0.5 / 4)
        #expect(abs(after.y - before.y) <= 0.5 / 4)
    }

    @Test func centeringIsExplicit() {
        let state = ZoomPanState(
            zoom: 1, offset: CGPoint(x: -40, y: 999), contentSize: CGSize(width: 100, height: 50),
            viewportSize: CGSize(width: 400, height: 300)
        )
        #expect(state.centered().offset == CGPoint(x: 150, y: 125))
    }

    @Test(arguments: [
        // Already inside: stays exactly where it is.
        (CGPoint(x: 40, y: 20), CGPoint(x: 40, y: 20)),
        // Partly outside: moved only as far as needed to be wholly visible.
        (CGPoint(x: 390, y: -5), CGPoint(x: 300, y: 0)),
    ])
    func clampingKeepsASmallImageWhereItIs(offset: CGPoint, expected: CGPoint) {
        let state = ZoomPanState(
            zoom: 1, offset: offset, contentSize: CGSize(width: 100, height: 50),
            viewportSize: CGSize(width: 400, height: 300))
        #expect(state.clamped().offset == expected)
    }

    @Test func clampingOffWholePixelsKeepsTheSameLimits() {
        // (zoom, offset, unrounded, on whole pixels), 100×50 in 400×300.
        let cases: [(CGFloat, CGPoint, CGPoint, CGPoint)] = [
            // Small image, inside: fractions kept unrounded, rounded down on whole pixels.
            (1, CGPoint(x: 40.7, y: 20.3), CGPoint(x: 40.7, y: 20.3), CGPoint(x: 40, y: 20)),
            // Small image, past the right and top edges: the same limits either way.
            (1, CGPoint(x: 390.4, y: -5.6), CGPoint(x: 300, y: 0), CGPoint(x: 300, y: 0)),
            // Large image (800×400), inside: fractions kept, rounded to nearest on whole pixels.
            (8, CGPoint(x: -120.6, y: -40.4), CGPoint(x: -120.6, y: -40.4), CGPoint(x: -121, y: -40)),
            // Large image, past its edges both ways: held at them.
            (8, CGPoint(x: 12.5, y: -171.25), CGPoint(x: 0, y: -100), CGPoint(x: 0, y: -100)),
        ]
        for (zoom, offset, unrounded, rounded) in cases {
            let state = ZoomPanState(
                zoom: zoom, offset: offset, contentSize: CGSize(width: 100, height: 50),
                viewportSize: CGSize(width: 400, height: 300))
            #expect(state.clamped(toWholePixels: false).offset == unrounded)
            #expect(state.clamped().offset == rounded)
            #expect(state.clamped(toWholePixels: true) == state.clamped())
        }
    }

    @Test func fitShowsTheWholeImageCentred() {
        let state = ZoomPanState(
            zoom: 7, offset: CGPoint(x: -300, y: -300), contentSize: CGSize(width: 400, height: 300),
            viewportSize: CGSize(width: 800, height: 450)
        )
        .fitted()
        #expect(state.zoom == 1.5)
        #expect(state.offset == CGPoint(x: 100, y: 0))
        #expect(state.isFit)
    }

    @Test func resizingByTheRightEdgeKeepsTheImageStill() {
        let state = ZoomPanState(
            zoom: 4, offset: CGPoint(x: -40, y: -8), contentSize: CGSize(width: 100, height: 60),
            viewportSize: CGSize(width: 200, height: 100))
        let resized = state.resizingContent(to: CGSize(width: 120, height: 60), originShift: .zero)
        #expect(resized.zoom == 4)
        #expect(resized.offset == state.offset)
    }

    @Test func resizingByTheLeftEdgeKeepsVisiblePixelsInPlace() {
        let state = ZoomPanState(
            zoom: 4, offset: CGPoint(x: -40, y: -8), contentSize: CGSize(width: 100, height: 60),
            viewportSize: CGSize(width: 200, height: 100))
        let point = CGPoint(x: 100, y: 50)
        let before = state.sourcePoint(forViewportPoint: point)
        // The left edge moved 10 source pixels to the left: the same screen pixel is now 10 further in.
        let resized = state.resizingContent(to: CGSize(width: 110, height: 60), originShift: CGPoint(x: -10, y: 0))
        let after = resized.sourcePoint(forViewportPoint: point)
        #expect(resized.zoom == 4)
        #expect(after.x == before.x + 10)
        #expect(after.y == before.y)
    }

    @Test func panStopsAtTheImageEdges() {
        let state = ZoomPanState(
            zoom: 8, contentSize: CGSize(width: 100, height: 100), viewportSize: CGSize(width: 400, height: 300))
        #expect(state.panned(by: CGPoint(x: 500, y: 500)).offset == .zero)
        #expect(state.panned(by: CGPoint(x: -5000, y: -5000)).offset == CGPoint(x: -400, y: -500))
    }

    @Test(arguments: [CGFloat(3), 2.5, 1.37, 7])
    func offsetIsAlwaysWholePixels(zoom: CGFloat) {
        let state = ZoomPanState(
            zoom: 1, contentSize: CGSize(width: 333, height: 217), viewportSize: CGSize(width: 401, height: 299)
        )
        .zoomed(to: zoom, around: CGPoint(x: 101.3, y: 77.7))
        #expect(state.offset.x == state.offset.x.rounded())
        #expect(state.offset.y == state.offset.y.rounded())
    }

    @Test(arguments: [CGFloat(1), 2, 4, 8, 16])
    func integerZoomMapsEverySourcePixelToAWholeSquare(zoom: CGFloat) {
        let state = ZoomPanState(
            zoom: 1, contentSize: CGSize(width: 50, height: 40), viewportSize: CGSize(width: 300, height: 200)
        )
        .zoomed(to: zoom, around: CGPoint(x: 123.4, y: 56.7))
        for x in 0..<50 {
            let left = state.viewportPoint(forSourcePoint: CGPoint(x: x, y: 0)).x
            let right = state.viewportPoint(forSourcePoint: CGPoint(x: x + 1, y: 0)).x
            #expect(left == left.rounded())
            #expect(right - left == zoom)
        }
    }

    @Test func sourcePixelUnderTheCursorAt800Percent() {
        let state = ZoomPanState(
            zoom: 8, contentSize: CGSize(width: 10, height: 10), viewportSize: CGSize(width: 80, height: 80))
        #expect(state.sourcePixel(atViewportPoint: CGPoint(x: 15.9, y: 8))! == (1, 1))
        #expect(state.sourcePixel(atViewportPoint: CGPoint(x: 79.9, y: 0))! == (9, 0))
        #expect(state.sourcePixel(atViewportPoint: CGPoint(x: -0.1, y: 0)) == nil)
        #expect(state.sourcePixel(atViewportPoint: CGPoint(x: 80, y: 0)) == nil)
    }

    @Test func imageRectPlacesAPartialImageInsideTheArea() {
        // A 100×60 area at 4×, panned by (-40, -8); the captured part starts 40 px into the area.
        let state = ZoomPanState(
            zoom: 4, offset: CGPoint(x: -40, y: -8), contentSize: CGSize(width: 100, height: 60),
            viewportSize: CGSize(width: 200, height: 100))
        let rect = state.imageRect(origin: CGPoint(x: 40, y: 0), size: CGSize(width: 60, height: 60))
        #expect(rect == CGRect(x: 120, y: -8, width: 240, height: 240))
    }

    @Test func fitZoomFitsTheLimitingAxis() {
        let state = ZoomPanState(
            contentSize: CGSize(width: 400, height: 300), viewportSize: CGSize(width: 800, height: 450))
        #expect(state.fitZoom == 1.5)
    }

    @Test(arguments: [
        (CGFloat(8), 1, CGFloat(12)),
        (8, -1, 6),
        (5, 1, 6),
        (5, -1, 4),
        (64, 1, 64),
    ])
    func keyboardZoomStepsAlongTheLadder(from zoom: CGFloat, direction: Int, expected: CGFloat) {
        let state = ZoomPanState(
            zoom: zoom, contentSize: CGSize(width: 10, height: 10), viewportSize: CGSize(width: 10, height: 10))
        #expect(state.steppedZoom(direction: direction) == expected)
    }

    @Test(arguments: [
        // viewport ÷ zoom comes out a float step under the content height.
        (CGSize(width: 3686, height: 1245), CGSize(width: 329, height: 3511)),
        // The fitted height comes out a float step over the viewport.
        (CGSize(width: 3466, height: 1855), CGSize(width: 3458, height: 2786)),
    ])
    func fitShowsTheWholeImageWithSizesThatDontDivide(viewport: CGSize, content: CGSize) {
        let state = ZoomPanState(contentSize: content, viewportSize: viewport).fitted()
        #expect(state.offset.x >= 0)
        #expect(state.offset.y >= 0)
        #expect(state.visibleSourceRect == nil)
    }

    @Test func centeringALargerImageStillGoesPastTheEdges() {
        let state = ZoomPanState(
            zoom: 4, contentSize: CGSize(width: 100, height: 50), viewportSize: CGSize(width: 300, height: 100)
        ).centered()
        #expect(state.offset == CGPoint(x: -50, y: -50))
    }

    @Test func visibleSourceRectIsThePartTheViewportShows() {
        // 400×200 at 8× in an 800×400 viewport: a 100×50 window onto the image.
        let state = ZoomPanState(
            zoom: 8, offset: CGPoint(x: -800, y: -400), contentSize: CGSize(width: 400, height: 200),
            viewportSize: CGSize(width: 800, height: 400))
        #expect(state.visibleSourceRect == CGRect(x: 100, y: 50, width: 100, height: 50))
        #expect(
            state.panned(by: CGPoint(x: 10_000, y: 10_000)).visibleSourceRect
                == CGRect(x: 0, y: 0, width: 100, height: 50))
    }

    @Test func visibleSourceRectIsClippedToTheImage() {
        // 800×200 scaled in a 400×400 viewport: cut left and right, but with room above and below.
        let state = ZoomPanState(
            zoom: 2, offset: CGPoint(x: -200, y: 100), contentSize: CGSize(width: 400, height: 100),
            viewportSize: CGSize(width: 400, height: 400))
        #expect(state.visibleSourceRect == CGRect(x: 100, y: 0, width: 200, height: 100))
    }

    @Test func visibleSourceRectKeepsAPartlyShownPixel() {
        // At 3× a 100 px viewport shows 33⅓ source pixels.
        let state = ZoomPanState(
            zoom: 3, offset: .zero, contentSize: CGSize(width: 90, height: 90),
            viewportSize: CGSize(width: 100, height: 300))
        #expect(state.visibleSourceRect == CGRect(x: 0, y: 0, width: CGFloat(100) / 3, height: 90))
    }

    @Test(arguments: [CGFloat(0.5), 1.5])
    func noVisibleSourceRectWhenTheWholeImageShows(zoom: CGFloat) {
        let state = ZoomPanState(
            zoom: zoom, contentSize: CGSize(width: 400, height: 300), viewportSize: CGSize(width: 800, height: 450)
        ).centered()
        #expect(state.visibleSourceRect == nil)
    }

    // MARK: Dragging the outline of the visible part

    /// 400×200 at 8× in an 800×400 viewport, showing 100×50 from (100, 50).
    private let zoomedIn = ZoomPanState(
        zoom: 8, offset: CGPoint(x: -800, y: -400), contentSize: CGSize(width: 400, height: 200),
        viewportSize: CGSize(width: 800, height: 400))

    @Test func movingTheVisiblePartMovesItBySourcePixels() {
        let moved = zoomedIn.movingVisiblePart(by: CGPoint(x: 10, y: -5))
        #expect(moved.visibleSourceRect == CGRect(x: 110, y: 45, width: 100, height: 50))
        #expect(moved.offset == CGPoint(x: -880, y: -360))
        #expect(moved.zoom == 8)
    }

    @Test func movingTheVisiblePartByNothingChangesNothing() {
        #expect(zoomedIn.movingVisiblePart(by: .zero) == zoomedIn)
    }

    @Test(arguments: [
        // Past each edge: the part stops at it.
        (CGPoint(x: -1000, y: 0), CGRect(x: 0, y: 50, width: 100, height: 50)),
        (CGPoint(x: 1000, y: 0), CGRect(x: 300, y: 50, width: 100, height: 50)),
        (CGPoint(x: 0, y: -1000), CGRect(x: 100, y: 0, width: 100, height: 50)),
        (CGPoint(x: 0, y: 1000), CGRect(x: 100, y: 150, width: 100, height: 50)),
        // Exactly to an edge, and to a corner.
        (CGPoint(x: -100, y: 0), CGRect(x: 0, y: 50, width: 100, height: 50)),
        (CGPoint(x: 200, y: 100), CGRect(x: 300, y: 150, width: 100, height: 50)),
        (CGPoint(x: -5000, y: 5000), CGRect(x: 0, y: 150, width: 100, height: 50)),
    ])
    func movingTheVisiblePartStopsAtTheImageEdges(delta: CGPoint, expected: CGRect) {
        let moved = zoomedIn.movingVisiblePart(by: delta)
        #expect(moved.visibleSourceRect == expected)
        // The same clamp as the Viewer's own panning, which moves the image the other way.
        #expect(moved == zoomedIn.panned(by: CGPoint(x: -delta.x * 8, y: -delta.y * 8)))
    }

    @Test(arguments: [
        // Zoom, and the viewport in drawable pixels: a 1× Viewer and a 2× one of the same size in points.
        (CGFloat(1), CGSize(width: 800, height: 500)), (CGFloat(1), CGSize(width: 1600, height: 1000)),
        (CGFloat(2), CGSize(width: 800, height: 500)), (CGFloat(8), CGSize(width: 1600, height: 1000)),
        (CGFloat(0.5), CGSize(width: 800, height: 500)), (CGFloat(2.5), CGSize(width: 1600, height: 1000)),
        (CGFloat(1.37), CGSize(width: 800, height: 500)),
    ])
    func movingTheVisiblePartByNPixelsMovesItByNPixels(zoom: CGFloat, viewport: CGSize) throws {
        let state = ZoomPanState(
            zoom: zoom, offset: CGPoint(x: (-1000 * zoom).rounded(), y: (-1000 * zoom).rounded()),
            contentSize: CGSize(width: 4000, height: 3000), viewportSize: viewport)
        let before = try #require(state.visibleSourceRect)
        let after = try #require(state.movingVisiblePart(by: CGPoint(x: 7, y: -3)).visibleSourceRect)
        #expect(abs(after.width - before.width) < 1e-9 && abs(after.height - before.height) < 1e-9)
        // The offset is whole drawable pixels: at a fractional zoom within half of one.
        let tolerance = 0.5 / zoom + 1e-9
        #expect(abs(after.minX - before.minX - 7) <= tolerance)
        #expect(abs(after.minY - before.minY + 3) <= tolerance)
        if zoom == zoom.rounded() {
            #expect(after.origin == CGPoint(x: before.minX + 7, y: before.minY - 3))
        }
    }

    @Test func movingTheVisiblePartLeavesAnAxisWhereTheWholeImageShows() {
        // 400×100 at 2× in a 400×400 viewport: cut left and right, the whole height with room around it.
        let state = ZoomPanState(
            zoom: 2, offset: CGPoint(x: -200, y: 100), contentSize: CGSize(width: 400, height: 100),
            viewportSize: CGSize(width: 400, height: 400))
        let moved = state.movingVisiblePart(by: CGPoint(x: 10, y: 30))
        #expect(moved.offset == CGPoint(x: -220, y: 100))
        #expect(moved.visibleSourceRect == CGRect(x: 110, y: 0, width: 200, height: 100))
    }
}
