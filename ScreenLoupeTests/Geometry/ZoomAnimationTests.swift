import CoreGraphics
import Foundation
import Testing

struct ZoomAnimationTests {
    /// 200×100 source pixels in an 800×600 viewport.
    private static let base = ZoomPanState(
        zoom: 1, contentSize: CGSize(width: 200, height: 100), viewportSize: CGSize(width: 800, height: 600))
    private static let center = CGPoint(x: 400, y: 300)
    private static let start: TimeInterval = 1000

    private static func time(_ fraction: Double) -> TimeInterval {
        start + fraction * ZoomAnimation.duration
    }

    private static func close(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 1e-6) -> Bool {
        abs(a - b) <= tolerance * max(1, abs(b))
    }

    private static func close(_ a: CGPoint, _ b: CGPoint, _ tolerance: CGFloat = 1e-6) -> Bool {
        close(a.x, b.x, tolerance) && close(a.y, b.y, tolerance)
    }

    /// 1× centred, then the preset zoom around the viewport centre.
    private static func preset(_ from: CGFloat, _ to: CGFloat) -> ZoomAnimation {
        var initial = base
        initial.zoom = from
        initial = initial.centered()
        return ZoomAnimation(from: initial, to: initial.zoomed(to: to, around: center), start: start)
    }

    private static let fractions: [Double] = [0.05, 0.1, 0.25, 0.4, 0.5, 0.6, 0.75, 0.9, 0.99]

    // MARK: Easing

    @Test func easingIsSymmetricAndPinned() {
        #expect(ZoomAnimation.eased(0) == 0)
        #expect(ZoomAnimation.eased(1) == 1)
        #expect(ZoomAnimation.eased(0.5) == 0.5)
        #expect(ZoomAnimation.eased(-1) == 0)
        #expect(ZoomAnimation.eased(2) == 1)
        for t in stride(from: CGFloat(0.05), to: 0.5, by: 0.05) {
            #expect(Self.close(ZoomAnimation.eased(t) + ZoomAnimation.eased(1 - t), 1, 1e-12))
        }
    }

    @Test func easingStartsAndEndsSlowly() {
        let early = ZoomAnimation.eased(0.1)
        let late = ZoomAnimation.eased(0.9)
        #expect(early < 0.1)
        #expect(late > 0.9)
        var previous: CGFloat = 0
        for t in stride(from: CGFloat(0.01), through: 1, by: 0.01) {
            let value = ZoomAnimation.eased(t)
            #expect(value >= previous)
            previous = value
        }
    }

    // MARK: Zoom

    @Test(arguments: [(CGFloat(1), CGFloat(16)), (16, 1)])
    func zoomChangesMonotonically(from: CGFloat, to: CGFloat) {
        let animation = Self.preset(from, to)
        var previous = animation.state(at: Self.time(0)).zoom
        for step in 1...100 {
            let zoom = animation.state(at: Self.time(Double(step) / 100)).zoom
            #expect(to > from ? zoom >= previous : zoom <= previous)
            previous = zoom
        }
        #expect(previous == to)
    }

    @Test(arguments: [(CGFloat(1), CGFloat(16)), (16, 1)])
    func halfTimeIsTheGeometricMidpoint(from: CGFloat, to: CGFloat) {
        let zoom = Self.preset(from, to).state(at: Self.time(0.5)).zoom
        #expect(Self.close(zoom, 4))
    }

    @Test func zoomIsEvenInLogSpace() {
        // At eased progress e the zoom is 1 · 16^e.
        let animation = Self.preset(1, 16)
        for fraction in Self.fractions {
            let e = ZoomAnimation.eased(CGFloat(fraction))
            #expect(Self.close(animation.state(at: Self.time(fraction)).zoom, pow(16, e)))
        }
    }

    // MARK: The still point

    @Test(arguments: [(CGFloat(1), CGFloat(16)), (16, 1), (1, 2), (8, 4), (1.5, 3.7)])
    func presetKeepsTheViewportCentreStill(from: CGFloat, to: CGFloat) {
        let animation = Self.preset(from, to)
        // A centred image zoomed around the centre needs no clamp: the still point is the centre the
        // command zoomed around. (A clamped or centring target is `fitGlidesZoomAndPanTogether`.)
        #expect(Self.close(animation.anchor ?? .zero, Self.center, 1e-9))
        let still = animation.anchor ?? .zero
        let source = animation.from.sourcePoint(forViewportPoint: still)
        for fraction in Self.fractions {
            let shown = animation.state(at: Self.time(fraction)).viewportPoint(forSourcePoint: source)
            #expect(Self.close(shown, still, 1e-6))
        }
    }

    @Test func zoomAroundACursorKeepsItStill() {
        let from = ZoomPanState(
            zoom: 8, offset: CGPoint(x: -400, y: -200), contentSize: CGSize(width: 200, height: 100),
            viewportSize: CGSize(width: 800, height: 600))
        let cursor = CGPoint(x: 317, y: 211)
        let to = from.zoomed(to: 16, around: cursor)
        let animation = ZoomAnimation(from: from, to: to, start: Self.start)
        let still = animation.anchor ?? .zero
        // The target's offset is rounded to whole pixels, so the still point is within a pixel of
        // the cursor.
        #expect(abs(still.x - cursor.x) <= 1)
        #expect(abs(still.y - cursor.y) <= 1)
        let source = from.sourcePoint(forViewportPoint: still)
        for fraction in Self.fractions {
            let shown = animation.state(at: Self.time(fraction)).viewportPoint(forSourcePoint: source)
            #expect(Self.close(shown, still))
        }
    }

    // MARK: Fit

    @Test(arguments: [CGFloat(16), 0.25])
    func fitGlidesZoomAndPanTogether(zoom: CGFloat) {
        // Off centre at 16× (zoomed in past Fit) or at 0.25× (below Fit), then Fit, which also centres.
        let from = ZoomPanState(
            zoom: zoom, offset: CGPoint(x: zoom > 1 ? -1200 : 12, y: zoom > 1 ? -300 : 40),
            contentSize: CGSize(width: 200, height: 100), viewportSize: CGSize(width: 800, height: 600)
        )
        .clamped()
        let to = from.fitted()
        #expect(to.zoom == 4)
        let animation = ZoomAnimation(from: from, to: to, start: Self.start)
        let still = animation.anchor ?? .zero
        let source = from.sourcePoint(forViewportPoint: still)
        var previousZoom = from.zoom
        for fraction in Self.fractions {
            let shown = animation.state(at: Self.time(fraction))
            // Still wherever the pan limits allow; held at them where the free glide would pass them.
            let raw = Self.unclamped(animation, zoom: shown.zoom, anchor: still)
            let limits = Self.limits(shown)
            if limits.x.contains(raw.x) && limits.y.contains(raw.y) {
                #expect(Self.close(shown.viewportPoint(forSourcePoint: source), still, 1e-6))
            } else {
                #expect(limits.x.contains(shown.offset.x) && limits.y.contains(shown.offset.y))
            }
            #expect(zoom > 4 ? shown.zoom <= previousZoom : shown.zoom >= previousZoom)
            previousZoom = shown.zoom
        }
        #expect(animation.state(at: Self.time(1)) == to)
    }

    // MARK: Pan limits

    /// The offset range a pan is kept in on one axis, at `content` scaled pixels.
    private static func limits(content: CGFloat, viewport: CGFloat) -> ClosedRange<CGFloat> {
        content <= viewport ? 0...(viewport - content) : (viewport - content)...0
    }

    private static func limits(_ state: ZoomPanState) -> (x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>) {
        (
            limits(content: state.scaledContentSize.width, viewport: state.viewportSize.width),
            limits(content: state.scaledContentSize.height, viewport: state.viewportSize.height)
        )
    }

    /// The offset that keeps `anchor` still at `zoom`, before any clamp.
    private static func unclamped(_ animation: ZoomAnimation, zoom: CGFloat, anchor: CGPoint) -> CGPoint {
        let scale = zoom / animation.from.zoom
        return CGPoint(
            x: anchor.x - (anchor.x - animation.from.offset.x) * scale,
            y: anchor.y - (anchor.y - animation.from.offset.y) * scale)
    }

    /// Fit (4×: 800×400 in 800×600, 100 px above and below), then 16× around a point near an edge.
    private static let edgePoints = [
        CGPoint(x: 790, y: 110), CGPoint(x: 5, y: 495), CGPoint(x: 400, y: 104), CGPoint(x: 795, y: 590),
    ]

    @Test(arguments: edgePoints)
    func fitTo16AroundAnEdgeNeverLeavesThePanLimits(cursor: CGPoint) {
        let from = Self.base.fitted()
        #expect(from.zoom == 4)
        let animation = ZoomAnimation(from: from, to: from.zoomed(to: 16, around: cursor), start: Self.start)
        let anchor = animation.anchor ?? .zero
        var clampedSomewhere = false
        for step in 0...1000 {
            let shown = animation.state(at: Self.time(Double(step) / 1000))
            let limits = Self.limits(shown)
            #expect(limits.x.contains(shown.offset.x) && limits.y.contains(shown.offset.y))
            let raw = Self.unclamped(animation, zoom: shown.zoom, anchor: anchor)
            if limits.x.contains(raw.x) && limits.y.contains(raw.y) {
                // Within the limits the anchor stays still.
                #expect(Self.close(shown.offset, raw, 1e-6))
            } else {
                clampedSomewhere = true
            }
        }
        // Without the clamp this glide would go past the edges: the test does test the clamp.
        #expect(clampedSomewhere)
        #expect(animation.state(at: Self.time(1)) == animation.to)
    }

    @Test(arguments: edgePoints)
    func theClampedGlideIsContinuous(cursor: CGPoint) {
        // The clamp moves the offset no more than the free glide or the limits move between two
        // samples, so there is no jump where it starts or stops holding.
        let from = Self.base.fitted()
        let animation = ZoomAnimation(from: from, to: from.zoomed(to: 16, around: cursor), start: Self.start)
        let anchor = animation.anchor ?? .zero
        var previous = animation.state(at: Self.time(0))
        var previousRaw = Self.unclamped(animation, zoom: previous.zoom, anchor: anchor)
        for step in 1...1000 {
            let shown = animation.state(at: Self.time(Double(step) / 1000))
            let raw = Self.unclamped(animation, zoom: shown.zoom, anchor: anchor)
            let limits = Self.limits(shown)
            let previousLimits = Self.limits(previous)
            let boundMoveX = max(
                abs(limits.x.lowerBound - previousLimits.x.lowerBound),
                abs(limits.x.upperBound - previousLimits.x.upperBound))
            let boundMoveY = max(
                abs(limits.y.lowerBound - previousLimits.y.lowerBound),
                abs(limits.y.upperBound - previousLimits.y.upperBound))
            #expect(abs(shown.offset.x - previous.offset.x) <= max(abs(raw.x - previousRaw.x), boundMoveX) + 1e-6)
            #expect(abs(shown.offset.y - previous.offset.y) <= max(abs(raw.y - previousRaw.y), boundMoveY) + 1e-6)
            previous = shown
            previousRaw = raw
        }
        #expect(previous == animation.to)
    }

    @Test func aGlideInsideTheLimitsIsNotClamped() {
        // 8× → 16× around the middle of an image larger than the viewport, and Fit → 16× around a
        // point by the left edge at mid-height: nothing passes an edge, so the anchor stays still.
        let middle = ZoomPanState(
            zoom: 8, offset: CGPoint(x: -400, y: -100), contentSize: CGSize(width: 200, height: 100),
            viewportSize: CGSize(width: 800, height: 600))
        let fit = Self.base.fitted()
        for animation in [
            ZoomAnimation(from: middle, to: middle.zoomed(to: 16, around: Self.center), start: Self.start),
            ZoomAnimation(from: fit, to: fit.zoomed(to: 16, around: CGPoint(x: 12, y: 300)), start: Self.start),
        ] {
            Self.expectUnclamped(animation)
        }
    }

    private static func expectUnclamped(_ animation: ZoomAnimation) {
        let anchor = animation.anchor ?? .zero
        for step in 0...200 {
            let shown = animation.state(at: time(Double(step) / 200))
            #expect(close(shown.offset, unclamped(animation, zoom: shown.zoom, anchor: anchor), 1e-6))
        }
    }

    @Test func aPureGlidePansLinearlyInEasedTime() {
        // Fit at the Fit zoom already, but panned: only the pan moves, eased.
        let fit = Self.base.fitted()
        var from = fit
        from.offset = CGPoint(x: fit.offset.x, y: fit.offset.y + 40)
        let animation = ZoomAnimation(from: from, to: fit, start: Self.start)
        #expect(animation.anchor == nil)
        for fraction in Self.fractions {
            let shown = animation.state(at: Self.time(fraction))
            let e = ZoomAnimation.eased(CGFloat(fraction))
            #expect(shown.zoom == fit.zoom)
            #expect(Self.close(shown.offset.y, from.offset.y + (fit.offset.y - from.offset.y) * e, 1e-9))
            #expect(Self.close(shown.offset.x, fit.offset.x, 1e-9))
        }
    }

    @Test func aTinyZoomChangeMatchesThePurePan() {
        // Near r = 1 the weight (1 − r^e) / (1 − r) tends to e: no blow-up.
        var from = Self.base
        from.offset = CGPoint(x: 10, y: 20)
        var to = from
        to.zoom = 1 + 1e-12
        to.offset = CGPoint(x: 50, y: -20)
        let shown = ZoomAnimation(from: from, to: to, start: Self.start).state(at: Self.time(0.25))
        let e = ZoomAnimation.eased(0.25)
        #expect(Self.close(shown.offset.x, 10 + 40 * e, 1e-3))
        #expect(Self.close(shown.offset.y, 20 - 40 * e, 1e-3))
    }

    // MARK: Zooming without a pointer

    /// 500×200 at 4× (2000×800) in 1000×600, shown at its right part, then 1× about the image: the
    /// target is centred on both axes.
    private static func zoomOutToCentred(offsetX: CGFloat) -> ZoomAnimation {
        let from = ZoomPanState(
            zoom: 4, offset: CGPoint(x: offsetX, y: -100), contentSize: CGSize(width: 500, height: 200),
            viewportSize: CGSize(width: 1000, height: 600))
        return ZoomAnimation(from: from, to: from.zoomedAboutImage(to: 1), start: start)
    }

    /// 100×50 at 1× in 400×300, centred and then dragged against the left edge, then 16× about the
    /// image (the user's case): the image's centre, at viewport (50, 150), is the point to keep still.
    private static func smallImageAtTheLeftTo16x() -> ZoomAnimation {
        let from = ZoomPanState(
            zoom: 1, contentSize: CGSize(width: 100, height: 50), viewportSize: CGSize(width: 400, height: 300)
        ).centered().panned(by: CGPoint(x: -500, y: 0))
        return ZoomAnimation(from: from, to: from.zoomedAboutImage(to: 16), start: start)
    }

    /// Every edge of the image moves one way, without jumps (under `maxStep` pixels per 1/2000 of the
    /// glide), the view stays within the pan limits all the way, and it ends exactly at the model.
    private static func expectSmoothGlide(_ animation: ZoomAnimation, maxStep: CGFloat) {
        var previous = animation.state(at: Self.time(0))
        var directions: [CGFloat] = [0, 0, 0, 0]
        for step in 1...2000 {
            let shown = animation.state(at: Self.time(Double(step) / 2000))
            let limits = Self.limits(shown)
            #expect(limits.x.contains(shown.offset.x) && limits.y.contains(shown.offset.y))
            let edges = [
                shown.offset.x, shown.offset.x + shown.scaledContentSize.width,
                shown.offset.y, shown.offset.y + shown.scaledContentSize.height,
            ]
            let previousEdges = [
                previous.offset.x, previous.offset.x + previous.scaledContentSize.width,
                previous.offset.y, previous.offset.y + previous.scaledContentSize.height,
            ]
            for index in edges.indices {
                let move = edges[index] - previousEdges[index]
                #expect(abs(move) < maxStep)
                #expect(move * directions[index] >= -1e-9)
                if abs(move) > 1e-9 { directions[index] = move }
            }
            previous = shown
        }
        #expect(previous == animation.to)
    }

    @Test(arguments: [CGFloat(-1000), -500, 0])
    func aGlideToACentredImageEndsExactlyAtTheModel(offsetX: CGFloat) {
        let animation = Self.zoomOutToCentred(offsetX: offsetX)
        #expect(animation.to.offset == CGPoint(x: 250, y: 200))
        #expect(animation.state(at: Self.time(1)) == animation.to)
        // No jump at the end: just before it the view is a fraction of a pixel from the model.
        let last = animation.state(at: Self.time(0.999))
        #expect(abs(last.offset.x - animation.to.offset.x) < 0.01)
        #expect(abs(last.offset.y - animation.to.offset.y) < 0.01)
        #expect(Self.close(last.zoom, animation.to.zoom, 1e-4))
    }

    @Test(arguments: [CGFloat(-1000), -500, 0])
    func aGlideToACentredImageMovesEachEdgeOneWayAndWithinTheLimits(offsetX: CGFloat) {
        // The limits switch from covering the viewport to staying inside it midway. 2000 samples of a
        // 2000 px image shrinking to 500: no step near a jump.
        Self.expectSmoothGlide(Self.zoomOutToCentred(offsetX: offsetX), maxStep: 5)
    }

    @Test func aGlideAboutASmallImageAtTheLeftKeepsItsCentreStill() {
        let animation = Self.smallImageAtTheLeftTo16x()
        #expect(animation.from.offset == CGPoint(x: 0, y: 125))
        #expect(animation.to.offset == CGPoint(x: -750, y: -250))
        #expect(animation.anchor == CGPoint(x: 50, y: 150))
        #expect(animation.state(at: Self.time(1)) == animation.to)
        // Once the image covers the viewport (past 7× here) nothing holds it, and the image's centre
        // stays at (50, 150).
        for fraction in [0.8, 0.9, 0.99] {
            let shown = animation.state(at: Self.time(fraction))
            #expect(shown.zoom > 7)
            #expect(
                Self.close(shown.sourcePoint(forViewportPoint: CGPoint(x: 50, y: 150)), CGPoint(x: 50, y: 25), 1e-6))
        }
    }

    @Test func aGlideAboutASmallImageAtTheLeftHasNoJumps() {
        // 100 px growing to 1600 over 2000 samples.
        Self.expectSmoothGlide(Self.smallImageAtTheLeftTo16x(), maxStep: 5)
    }

    // MARK: Time

    @Test func beforeTheStartItShowsTheOrigin() {
        let animation = Self.preset(1, 16)
        #expect(animation.state(at: Self.start - 5) == animation.from)
        #expect(animation.state(at: Self.start) == animation.from)
        #expect(animation.progress(at: Self.start - 1) == 0)
        #expect(!animation.isFinished(at: Self.start))
    }

    @Test(arguments: [1.0, 1.0001, 3, 1000])
    func atTheEndItIsExactlyTheTarget(fraction: Double) {
        let animation = Self.preset(1, 16)
        #expect(animation.state(at: Self.time(fraction)) == animation.to)
        #expect(animation.isFinished(at: Self.time(fraction)))
    }

    @Test func justBeforeTheEndItIsNotFinished() {
        let animation = Self.preset(1, 16)
        #expect(!animation.isFinished(at: Self.time(0.999)))
        #expect(animation.state(at: Self.time(0.999)) != animation.to)
    }

    @Test(arguments: [TimeInterval(0), -0.2])
    func withoutLengthItIsOverAtOnce(duration: TimeInterval) {
        let from = Self.preset(1, 16).from
        let to = Self.preset(1, 16).to
        let animation = ZoomAnimation(from: from, to: to, start: Self.start, duration: duration)
        #expect(animation.isFinished(at: Self.start - 1))
        #expect(animation.state(at: Self.start - 1) == to)
        #expect(animation.state(at: Self.start) == to)
    }

    @Test func toItselfItStaysPut() {
        let state = Self.base.centered()
        let animation = ZoomAnimation(from: state, to: state, start: Self.start)
        #expect(animation.anchor == nil)
        for fraction in Self.fractions {
            #expect(animation.state(at: Self.time(fraction)) == state)
        }
    }

    // MARK: Retargeting

    @Test func retargetingMidwayDoesNotJump() {
        // 1× → 16×, and at a third of the way 1× again: it turns back from where it shows.
        let first = Self.preset(1, 16)
        let turn = Self.time(0.35)
        let shown = first.state(at: turn)
        let back = shown.zoomed(to: 1, around: Self.center)
        let second = first.retargeted(to: back, at: turn)
        #expect(second.from == shown)
        #expect(second.to == back)
        #expect(second.state(at: turn) == shown)
        // Continuous across the turn: a millisecond either side is a sliver of zoom apart.
        let before = first.state(at: turn - 0.001).zoom
        let after = second.state(at: turn + 0.001).zoom
        #expect(abs(after - before) / shown.zoom < 0.05)
        #expect(second.state(at: turn + ZoomAnimation.duration) == back)
    }

    @Test func retargetingKeepsTheDuration() {
        let first = ZoomAnimation(from: Self.preset(1, 16).from, to: Self.preset(1, 16).to, start: 5, duration: 0.5)
        let second = first.retargeted(to: first.from, at: 5.2)
        #expect(second.start == 5.2)
        #expect(second.duration == 0.5)
    }

    // MARK: Range

    @Test func extremeZoomsStayFiniteAndInRange() {
        let range = ZoomPanState.zoomRange
        let small = ZoomPanState(
            zoom: range.lowerBound, contentSize: CGSize(width: 4000, height: 3000),
            viewportSize: CGSize(width: 800, height: 600)
        )
        .centered()
        let large = small.zoomed(to: range.upperBound, around: Self.center)
        #expect(large.zoom == range.upperBound)
        for animation in [
            ZoomAnimation(from: small, to: large, start: Self.start),
            ZoomAnimation(from: large, to: small, start: Self.start),
        ] {
            for fraction in Self.fractions {
                let shown = animation.state(at: Self.time(fraction))
                #expect(shown.zoom.isFinite && shown.offset.x.isFinite && shown.offset.y.isFinite)
                #expect(shown.zoom >= range.lowerBound - 1e-9 && shown.zoom <= range.upperBound + 1e-9)
            }
            #expect(animation.state(at: Self.time(1)) == animation.to)
        }
        // Log-uniform: the midpoint of 0.05× → 64× is √(0.05 · 64) = √3.2.
        let mid = ZoomAnimation(from: small, to: large, start: Self.start).state(at: Self.time(0.5)).zoom
        #expect(Self.close(mid, (range.lowerBound * range.upperBound).squareRoot()))
    }

    @Test func nonIntegerZoomsGlideAndLandExactly() {
        let animation = Self.preset(1.37, 5.91)
        let mid = animation.state(at: Self.time(0.5)).zoom
        #expect(Self.close(mid, (1.37 * 5.91).squareRoot()))
        let end = animation.state(at: Self.time(1))
        #expect(end.zoom == animation.to.zoom)
        #expect(end.offset == animation.to.offset)
    }

    @Test func sizesComeFromTheTarget() {
        let animation = Self.preset(1, 16)
        let shown = animation.state(at: Self.time(0.5))
        #expect(shown.contentSize == animation.to.contentSize)
        #expect(shown.viewportSize == animation.to.viewportSize)
    }
}
