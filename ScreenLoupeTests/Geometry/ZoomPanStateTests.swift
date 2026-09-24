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
}
