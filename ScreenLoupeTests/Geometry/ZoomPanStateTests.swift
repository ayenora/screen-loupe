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

    // MARK: The centre of the visible part of the image

    @Test(arguments: [
        // Wholly visible.
        (CGPoint(x: 40, y: 20), CGPoint(x: 90, y: 45)),
        // Partly off the left, the right, the top, the bottom.
        (CGPoint(x: -60, y: 20), CGPoint(x: 20, y: 45)),
        (CGPoint(x: 350, y: 20), CGPoint(x: 375, y: 45)),
        (CGPoint(x: 40, y: -30), CGPoint(x: 90, y: 10)),
        (CGPoint(x: 40, y: 280), CGPoint(x: 90, y: 290)),
        // Off a corner.
        (CGPoint(x: -60, y: -30), CGPoint(x: 20, y: 10)),
    ])
    func visibleImageCenterIsTheCentreOfWhatShows(offset: CGPoint, expected: CGPoint) {
        // 100×50 at 1× in 400×300.
        let state = ZoomPanState(
            zoom: 1, offset: offset, contentSize: CGSize(width: 100, height: 50),
            viewportSize: CGSize(width: 400, height: 300))
        #expect(state.visibleImageCenter == expected)
    }

    @Test func visibleImageCenterScalesWithTheZoom() {
        // 100×50 at 2× is 200×100 at (40, 20).
        let state = ZoomPanState(
            zoom: 2, offset: CGPoint(x: 40, y: 20), contentSize: CGSize(width: 100, height: 50),
            viewportSize: CGSize(width: 400, height: 300))
        #expect(state.visibleImageCenter == CGPoint(x: 140, y: 70))
    }

    @Test func visibleImageCenterOfAnImageLargerOnOneAxisIsTheViewportsOnThatAxis() {
        // 500×50 at 1× in 400×300: wider than the viewport, shorter.
        let state = ZoomPanState(
            zoom: 1, offset: CGPoint(x: -100, y: 20), contentSize: CGSize(width: 500, height: 50),
            viewportSize: CGSize(width: 400, height: 300))
        #expect(state.visibleImageCenter == CGPoint(x: 200, y: 45))
    }

    @Test(arguments: [CGPoint(x: -37, y: -11), CGPoint(x: -600, y: -700), .zero])
    func visibleImageCenterOfAnImageCoveringTheViewportIsTheViewportsCentre(offset: CGPoint) {
        let state = ZoomPanState(
            zoom: 1, offset: offset, contentSize: CGSize(width: 1000, height: 1000),
            viewportSize: CGSize(width: 400, height: 300))
        #expect(state.visibleImageCenter == CGPoint(x: 200, y: 150))
    }

    @Test(arguments: [CGFloat(1), 2])
    func visibleImageCenterIsTheSameOnA1xAndA2xDisplay(scale: CGFloat) {
        // The same Capture Area and Viewer in points, partly off the left.
        let state = ZoomPanState(
            zoom: 1, offset: CGPoint(x: -60 * scale, y: 20 * scale),
            contentSize: CGSize(width: 100 * scale, height: 50 * scale),
            viewportSize: CGSize(width: 400 * scale, height: 300 * scale))
        #expect(state.visibleImageCenter == CGPoint(x: 20 * scale, y: 45 * scale))
    }

    @Test func visibleImageCenterWithNothingShowingIsTheViewportsCentre() {
        // Wholly off the viewport, no image, no viewport.
        let off = ZoomPanState(
            zoom: 1, offset: CGPoint(x: 500, y: 20), contentSize: CGSize(width: 100, height: 50),
            viewportSize: CGSize(width: 400, height: 300))
        #expect(off.visibleImageCenter == CGPoint(x: 200, y: 150))
        let noImage = ZoomPanState(
            zoom: 1, offset: CGPoint(x: 40, y: 20), contentSize: .zero, viewportSize: CGSize(width: 400, height: 300))
        #expect(noImage.visibleImageCenter == CGPoint(x: 200, y: 150))
        let noViewport = ZoomPanState(
            zoom: 1, offset: CGPoint(x: 40, y: 20), contentSize: CGSize(width: 100, height: 50), viewportSize: .zero)
        #expect(noViewport.visibleImageCenter == .zero)
    }

    // MARK: Zooming without a pointer

    @Test(arguments: [CGFloat(1), 2])
    func zoomingASmallImageDraggedLeftShowsItsCentre(scale: CGFloat) {
        // The user's case: 100×50 centred at 1× in 400×300, dragged against the left edge, then 16×.
        // The image's centre, at viewport (50, 150), stays there; around the viewport's centre the
        // Viewer would show only the image's right part.
        let dragged = ZoomPanState(
            zoom: 1, contentSize: CGSize(width: 100 * scale, height: 50 * scale),
            viewportSize: CGSize(width: 400 * scale, height: 300 * scale)
        ).centered().panned(by: CGPoint(x: -500 * scale, y: 0))
        #expect(dragged.offset == CGPoint(x: 0, y: 125 * scale))
        let zoomed = dragged.zoomedAboutImage(to: 16)
        #expect(zoomed.zoom == 16)
        #expect(zoomed.offset == CGPoint(x: -750 * scale, y: -250 * scale))
        #expect(
            zoomed.sourcePoint(forViewportPoint: CGPoint(x: 50 * scale, y: 150 * scale))
                == CGPoint(x: 50 * scale, y: 25 * scale))
        // It shows 46.875…71.875 of 0…100 across: the middle, not the right edge.
        let visible = zoomed.visibleSourceRect
        #expect(visible == CGRect(x: 46.875 * scale, y: 15.625 * scale, width: 25 * scale, height: 18.75 * scale))
        let aroundViewportCentre = dragged.zoomed(
            to: 16, around: CGPoint(x: 200 * scale, y: 150 * scale))
        #expect(aroundViewportCentre.visibleSourceRect?.maxX == 100 * scale)
    }

    @Test(arguments: [CGFloat(2), 4])
    func zoomingInASmallImageDraggedAsideGrowsItFromTheCentre(zoom: CGFloat) {
        // 100×50 at 1× in 400×300 dragged to (20, 40); at 2× (200×100) and 4× (400×200) it is no
        // larger than the viewport: centred.
        let state = ZoomPanState(
            zoom: 1, offset: CGPoint(x: 20, y: 40), contentSize: CGSize(width: 100, height: 50),
            viewportSize: CGSize(width: 400, height: 300))
        let zoomed = state.zoomedAboutImage(to: zoom)
        #expect(zoomed.offset == CGPoint(x: (400 - 100 * zoom) / 2, y: (300 - 50 * zoom) / 2))
    }

    @Test(arguments: [CGFloat(-1000), -500, 0])
    func zoomingOutAShiftedImageBelowTheViewportCentresIt(offsetX: CGFloat) {
        // 500×200 at 4× (2000×800) in 1000×600, shown at its right part, middle, left part; 1× is
        // 500×200, smaller on both axes. Anchored alone it would land off centre.
        let state = ZoomPanState(
            zoom: 4, offset: CGPoint(x: offsetX, y: -100), contentSize: CGSize(width: 500, height: 200),
            viewportSize: CGSize(width: 1000, height: 600))
        let zoomed = state.zoomedAboutImage(to: 1)
        #expect(zoomed.zoom == 1)
        #expect(zoomed.offset == CGPoint(x: 250, y: 200))
    }

    @Test(arguments: [
        // Shown at the bottom: 1.5× is still taller than the viewport, so it stays against the bottom.
        (CGFloat(-1600), CGFloat(-350)),
        // Shown in between: the source point at the centre stays there.
        (-520, -70),
        // Shown at the top: stays against the top.
        (0, 0),
    ])
    func zoomingOutBelowTheViewportOnOneAxisCentresOnlyThatAxis(offsetY: CGFloat, expectedY: CGFloat) {
        // 500×500 at 4× (2000×2000) in 1000×400, showing its right part; 1.5× is 750×750: narrower
        // than the viewport, still taller.
        let state = ZoomPanState(
            zoom: 4, offset: CGPoint(x: -1000, y: offsetY), contentSize: CGSize(width: 500, height: 500),
            viewportSize: CGSize(width: 1000, height: 400))
        let zoomed = state.zoomedAboutImage(to: 1.5)
        #expect(zoomed.offset == CGPoint(x: 125, y: expectedY))
    }

    @Test(arguments: [CGFloat(12), 4, 2.5])
    func zoomingALargeImageIsAroundTheViewportCentre(zoom: CGFloat) {
        // 200×100 at 8× (1600×800) in 800×600 covers the viewport: the visible part's centre is the
        // viewport's, and a zoom that stays larger on both axes is the zoom around it.
        let state = ZoomPanState(
            zoom: 8, offset: CGPoint(x: -400, y: -100), contentSize: CGSize(width: 200, height: 100),
            viewportSize: CGSize(width: 800, height: 600))
        let aroundCentre = state.zoomed(to: zoom, around: CGPoint(x: 400, y: 300))
        let zoomed = state.zoomedAboutImage(to: zoom)
        #expect(zoomed.zoom == zoom)
        if zoom == 12 {
            #expect(zoomed == aroundCentre)
            #expect(zoomed.sourcePoint(forViewportPoint: CGPoint(x: 400, y: 300)) == CGPoint(x: 100, y: 50))
        } else {
            // 4× is 800×400 and 2.5× 500×250: centred where no larger than the viewport.
            #expect(zoomed.offset.y == ((600 - 100 * zoom) / 2).rounded(.down))
            #expect(zoomed.offset.x == (zoom == 4 ? 0 : 150))
        }
    }

    @Test func zoomingAnImageLargerOnOneAxisIsAroundTheCentreOfWhatShows() {
        // 500×50 at 1× in 400×300 at (−100, 20): what shows is centred at (200, 45). 2× is 1000×100:
        // the source point at x 200 stays there, and the image is centred vertically.
        let state = ZoomPanState(
            zoom: 1, offset: CGPoint(x: -100, y: 20), contentSize: CGSize(width: 500, height: 50),
            viewportSize: CGSize(width: 400, height: 300))
        #expect(state.zoomedAboutImage(to: 2).offset == CGPoint(x: -400, y: 100))
    }

    @Test func zoomingInAroundTheCentreGrowsFromItThenFillsTheViewport() {
        // 100×50 at 1× in 400×300, zoomed in step by step: the image stays centred while it is
        // smaller, and then the centre source pixel stays at the centre, the image covering the
        // viewport on each larger axis.
        var state = ZoomPanState(
            zoom: 1, contentSize: CGSize(width: 100, height: 50), viewportSize: CGSize(width: 400, height: 300)
        ).centered()
        let center = CGPoint(x: 200, y: 150)
        let expected: [(CGFloat, CGPoint)] = [
            (2, CGPoint(x: 100, y: 100)), (4, CGPoint(x: 0, y: 50)), (8, CGPoint(x: -200, y: -50)),
            (16, CGPoint(x: -600, y: -250)),
        ]
        for (zoom, offset) in expected {
            state = state.zoomedAboutImage(to: zoom)
            #expect(state.offset == offset)
            #expect(state.sourcePoint(forViewportPoint: center) == CGPoint(x: 50, y: 25))
        }
    }

    @Test(arguments: [
        // Odd slack: 400 − 101 = 299 and 300 − 51 = 249, half rounded down.
        (CGFloat(1), CGPoint(x: 149, y: 124)),
        // 303×153: slack 97 and 147.
        (CGFloat(3), CGPoint(x: 48, y: 73)),
        // 252.5×127.5: slack 147.5 and 172.5, half of it 73.75 and 86.25.
        (CGFloat(2.5), CGPoint(x: 73, y: 86)),
    ])
    func theCentredOffsetIsWholePixels(zoom: CGFloat, expected: CGPoint) {
        let state = ZoomPanState(
            zoom: 3.9, offset: CGPoint(x: -17, y: -3), contentSize: CGSize(width: 101, height: 51),
            viewportSize: CGSize(width: 400, height: 300))
        #expect(state.zoomedAboutImage(to: zoom).offset == expected)
    }

    @Test(arguments: [CGFloat(1), 2])
    func zoomOutCentresTheSameOnA1xAndA2xDisplay(scale: CGFloat) {
        // The same Capture Area and Viewer in points: on a 2× display both have twice the pixels.
        // 300×200 at 4× (1200×800) in 1000×600, shown at its bottom-right; 2× is 600×400, centred.
        let state = ZoomPanState(
            zoom: 4, offset: CGPoint(x: -200 * scale, y: -200 * scale),
            contentSize: CGSize(width: 300 * scale, height: 200 * scale),
            viewportSize: CGSize(width: 1000 * scale, height: 600 * scale))
        let zoomed = state.zoomedAboutImage(to: 2)
        #expect(zoomed.offset == CGPoint(x: 200 * scale, y: 100 * scale))
    }

    @Test func panningASmallImageAfterAZoomStaysFree() {
        // Centring is a command zoom's: a pan afterwards moves a smaller image anywhere inside the
        // viewport.
        let zoomed = ZoomPanState(
            zoom: 4, offset: CGPoint(x: -1000, y: -100), contentSize: CGSize(width: 500, height: 200),
            viewportSize: CGSize(width: 1000, height: 600)
        ).zoomedAboutImage(to: 1)
        #expect(zoomed.panned(by: CGPoint(x: -200, y: 150)).offset == CGPoint(x: 50, y: 350))
    }

    @Test func resizingTheViewportKeepsASmallImageWhereItIs() {
        // Not a zoom: a smaller image off centre stays where it is when the viewport grows.
        var state = ZoomPanState(
            zoom: 1, offset: CGPoint(x: 40, y: 20), contentSize: CGSize(width: 100, height: 50),
            viewportSize: CGSize(width: 400, height: 300))
        state.viewportSize = CGSize(width: 600, height: 500)
        #expect(state.clamped().offset == CGPoint(x: 40, y: 20))
        let resized = state.resizingContent(to: CGSize(width: 120, height: 50), originShift: .zero)
        #expect(resized.offset == CGPoint(x: 40, y: 20))
    }

    // MARK: Zooming around the pointer

    @Test(arguments: [CGPoint(x: 317, y: 211), CGPoint(x: 5, y: 590), CGPoint(x: 795, y: 3)])
    func wheelZoomWhileLargerKeepsThePointerPixelExactly(pointer: CGPoint) {
        // 200×100 at 8× (1600×800) in 800×600, 12× around the pointer: larger both before and after,
        // and nothing reaches an edge, so the offset is the anchored one, rounded to whole pixels.
        let state = ZoomPanState(
            zoom: 8, offset: CGPoint(x: -400, y: -100), contentSize: CGSize(width: 200, height: 100),
            viewportSize: CGSize(width: 800, height: 600))
        let zoomed = state.zoomed(to: 12, around: pointer)
        let anchored = CGPoint(
            x: pointer.x - (pointer.x - state.offset.x) * 1.5, y: pointer.y - (pointer.y - state.offset.y) * 1.5)
        #expect(anchored.x <= 0 && anchored.x >= 800 - 2400 && anchored.y <= 0 && anchored.y >= 600 - 1200)
        #expect(zoomed.offset == CGPoint(x: anchored.x.rounded(), y: anchored.y.rounded()))
    }

    @Test(arguments: [
        // One tick in: the source point under the pointer, (40, 25), stays; the image stays at the
        // left, not centred (137, 118).
        (CGFloat(1.25), CGPoint(x: 10, y: 33)),
        // One tick out.
        (CGFloat(0.8), CGPoint(x: 28, y: 45)),
    ])
    func wheelTickOnASmallImageDraggedAsideOnlyZoomsAroundThePointer(zoom: CGFloat, expected: CGPoint) {
        // 100×50 at 1× in 400×300, dragged to (20, 40); the pointer at (60, 65).
        let state = ZoomPanState(
            zoom: 1, offset: CGPoint(x: 20, y: 40), contentSize: CGSize(width: 100, height: 50),
            viewportSize: CGSize(width: 400, height: 300))
        let zoomed = state.zoomed(to: zoom, around: CGPoint(x: 60, y: 65))
        #expect(zoomed.offset == expected)
        let underPointer = zoomed.sourcePoint(forViewportPoint: CGPoint(x: 60, y: 65))
        #expect(abs(underPointer.x - 40) < 1 / zoom && abs(underPointer.y - 25) < 1 / zoom)
    }

    @Test(arguments: [
        // Anchored inside the limits: stays where the pointer holds it, off centre (100, 100).
        (CGPoint(x: 100, y: 150), CGPoint(x: 75, y: 100)),
        // Anchored at (292.5, 205), past the right and bottom: held against them, not centred.
        (CGPoint(x: 390, y: 290), CGPoint(x: 200, y: 200)),
    ])
    func wheelZoomOutBelowTheViewportStaysAnchoredAndClamped(pointer: CGPoint, expected: CGPoint) {
        // 100×50 at 8× (800×400) in 400×300, against the left edge; 2× is 200×100, smaller on both.
        let state = ZoomPanState(
            zoom: 8, offset: CGPoint(x: 0, y: -50), contentSize: CGSize(width: 100, height: 50),
            viewportSize: CGSize(width: 400, height: 300))
        #expect(state.zoomed(to: 2, around: pointer).offset == expected)
    }

    @Test(arguments: [
        (CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 0)),
        (CGPoint(x: 317, y: 211), CGPoint(x: 237, y: 158)),
        // Anchored at (599.25, 449.25): past the right and bottom, held at them.
        (CGPoint(x: 799, y: 599), CGPoint(x: 400, y: 400)),
        (CGPoint(x: 400, y: 300), CGPoint(x: 300, y: 225)),
    ])
    func wheelZoomThatEndsSmallerStaysWhereThePointerHoldsIt(pointer: CGPoint, expected: CGPoint) {
        // 200×100 at 8× in 800×600, shown at its top-left corner; 2× is 400×200, smaller on both axes.
        let state = ZoomPanState(
            zoom: 8, offset: .zero, contentSize: CGSize(width: 200, height: 100),
            viewportSize: CGSize(width: 800, height: 600))
        #expect(state.zoomed(to: 2, around: pointer).offset == expected)
    }

    @Test(arguments: [
        (CGPoint(x: 10, y: 10), CGPoint(x: 200, y: 200)),
        (CGPoint(x: 200, y: 150), CGPoint(x: 100, y: 100)),
        (CGPoint(x: 390, y: 290), CGPoint(x: 0, y: 0)),
    ])
    func pointerZoomOnASmallImageIsAnchoredNotCentred(pointer: CGPoint, expected: CGPoint) {
        // 100×50 centred at 1× in 400×300; 2× is 200×100, still smaller: anchored at 2·offset −
        // pointer, then kept inside the viewport.
        let state = ZoomPanState(
            zoom: 1, contentSize: CGSize(width: 100, height: 50), viewportSize: CGSize(width: 400, height: 300)
        ).centered()
        #expect(state.offset == CGPoint(x: 150, y: 125))
        #expect(state.zoomed(to: 2, around: pointer).offset == expected)
    }

    @Test func zoomingInASmallImageNearAnEdgePinsItToTheWall() {
        // 100×50 centred at 1× in 400×300, 8× (800×400) around a point by the image's top-left
        // corner: anchored, the image would leave a gap at the left and top, so it stays against them.
        let state = ZoomPanState(
            zoom: 1, contentSize: CGSize(width: 100, height: 50), viewportSize: CGSize(width: 400, height: 300)
        ).centered()
        let zoomed = state.zoomed(to: 8, around: CGPoint(x: 160, y: 130))
        #expect(zoomed.offset == .zero)
        // The opposite corner: against the right and bottom.
        #expect(state.zoomed(to: 8, around: CGPoint(x: 240, y: 170)).offset == CGPoint(x: -400, y: -100))
    }

    @Test(arguments: [CGPoint.zero, CGPoint(x: 400, y: 300), CGPoint(x: 37, y: 281)])
    func zoomingToExactlyTheViewportSizeFillsItFromTheCorner(pointer: CGPoint) {
        // 100×75 at 4× is exactly 400×300: no slack either way, with or without a pointer.
        for from in [
            ZoomPanState(
                zoom: 8, offset: CGPoint(x: -400, y: -300), contentSize: CGSize(width: 100, height: 75),
                viewportSize: CGSize(width: 400, height: 300)),
            ZoomPanState(
                zoom: 1, offset: CGPoint(x: 3, y: 220), contentSize: CGSize(width: 100, height: 75),
                viewportSize: CGSize(width: 400, height: 300)),
        ] {
            for zoomed in [from.zoomed(to: 4, around: pointer), from.zoomedAboutImage(to: 4)] {
                #expect(zoomed.scaledContentSize == zoomed.viewportSize)
                #expect(zoomed.offset == .zero)
            }
        }
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
