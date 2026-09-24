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
        .clamped()
        let before = start.sourcePoint(forViewportPoint: anchor)
        let zoomed = start.zoomed(to: 4, around: anchor)
        let after = zoomed.sourcePoint(forViewportPoint: anchor)
        #expect(zoomed.zoom == 4)
        #expect(abs(after.x - before.x) <= 0.5 / 4)
        #expect(abs(after.y - before.y) <= 0.5 / 4)
    }

    @Test func smallImageIsCentred() {
        let state = ZoomPanState(
            zoom: 1, offset: CGPoint(x: -40, y: 999), contentSize: CGSize(width: 100, height: 50),
            viewportSize: CGSize(width: 400, height: 300)
        )
        .clamped()
        #expect(state.offset == CGPoint(x: 150, y: 125))
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
