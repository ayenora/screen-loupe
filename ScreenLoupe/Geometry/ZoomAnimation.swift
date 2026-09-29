import CoreGraphics
import Foundation

/// The glide of a zoom command (docs/product.md, Zoom and pan; docs/design.md §3): the model jumps
/// to `to` at once, and the Viewer shows `state(at:)`, which goes from `from` to `to` over
/// `duration` seconds from `start`.
///
/// The zoom moves evenly in log space, z = z0 · r^e with r = z1 / z0, and the offset so that the
/// point that stays still between the two views stays still all the way:
/// o = o0 + (o1 − o0) · (1 − r^e) / (1 − r), which is o0 + (o1 − o0) · e when the zoom doesn't
/// change. `e` is `eased` progress. The still point (`anchor`) is the one the command zoomed around
/// when the pan kept it in place; when the command also pans (Fit centring, a clamp at an edge) it is
/// the point both views share, so the pan glides with the zoom instead of on a line of its own.
///
/// Midway that offset can take the image past the bounds a pan is kept in (zooming in around a point
/// near an edge), so it is clamped to them, not rounded: the image never leaves its allowed range,
/// and the anchor stays still wherever the bounds allow.
///
/// A zoom about the image (`throughFill`, `ZoomPanState.zoomedAboutImage`) has no point to keep
/// still: it brings the centre of what shows to the viewport's centre. On an axis where it passes the
/// zoom at which the image spans the viewport exactly, the offset can only be 0 there, so it goes
/// o0 → 0 → o1, each stretch affine in the zoom. Without that knot the clamp pins the image to one
/// wall and then the other, and the centre it brings over swings back (a small image at the left
/// going to 16×: from the viewport's centre at 4× back to a quarter of the width at 6×). Each stretch
/// runs between two views within the bounds and so stays within them: the image's edges move one way,
/// and the centre of a small image shown whole never turns back on its way to the viewport's centre.
struct ZoomAnimation: Equatable, Sendable {
    static let duration: TimeInterval = 0.2

    let from: ZoomPanState
    let to: ZoomPanState
    /// Seconds on the clock `state(at:)` is given.
    let start: TimeInterval
    let duration: TimeInterval
    /// A zoom about the image: the offset goes through 0 where the image spans the viewport.
    let throughFill: Bool

    init(
        from: ZoomPanState, to: ZoomPanState, start: TimeInterval, duration: TimeInterval = Self.duration,
        throughFill: Bool = false
    ) {
        self.from = from
        self.to = to
        self.start = start
        self.duration = duration
        self.throughFill = throughFill
    }

    /// Cubic ease-in-out of `t` in 0…1: symmetric, so half the time is half the way.
    static func eased(_ t: CGFloat) -> CGFloat {
        let t = min(max(t, 0), 1)
        if t < 0.5 { return 4 * t * t * t }
        let back = 2 - 2 * t
        return 1 - back * back * back / 2
    }

    /// Linear progress at `time`, 0…1. An animation without length is over from the start.
    func progress(at time: TimeInterval) -> CGFloat {
        guard duration > 0 else { return 1 }
        return CGFloat(min(max((time - start) / duration, 0), 1))
    }

    func isFinished(at time: TimeInterval) -> Bool {
        progress(at: time) >= 1
    }

    /// The view shown at `time`: exactly `from` until it starts, exactly `to` once it is over.
    func state(at time: TimeInterval) -> ZoomPanState {
        let p = progress(at: time)
        if p <= 0 { return from }
        if p >= 1 { return to }
        let e = Self.eased(p)
        let logRatio = log(to.zoom / from.zoom)
        var next = to
        next.zoom = from.zoom * exp(e * logRatio)
        next.offset = CGPoint(
            x: axisOffset(
                from: from.offset.x, to: to.offset.x, e: e, logRatio: logRatio,
                fillZoom: to.viewportSize.width / to.contentSize.width),
            y: axisOffset(
                from: from.offset.y, to: to.offset.y, e: e, logRatio: logRatio,
                fillZoom: to.viewportSize.height / to.contentSize.height))
        return next.clamped(toWholePixels: false)
    }

    /// The offset on one axis at eased progress `e`: affine in the zoom, (z − z0) / (z1 − z0) of the
    /// way, which is (1 − r^e) / (1 − r). With `throughFill`, when the glide passes `fillZoom`, where
    /// the image spans the viewport exactly, it goes through 0 there: o0 to 0, then 0 to o1.
    private func axisOffset(
        from o0: CGFloat, to o1: CGFloat, e: CGFloat, logRatio: CGFloat, fillZoom: CGFloat
    )
        -> CGFloat
    {
        guard logRatio != 0 else { return o0 + (o1 - o0) * e }
        // z − z0 and z1 − z0 with expm1 for precision when the zoom barely changes.
        let z0 = from.zoom
        let moved = z0 * expm1(e * logRatio)
        let whole = z0 * expm1(logRatio)
        let crosses = throughFill && fillZoom.isFinite && (fillZoom - z0) * (fillZoom - to.zoom) < 0
        guard crosses else { return o0 + (o1 - o0) * moved / whole }
        let toFill = fillZoom - z0
        if abs(moved) <= abs(toFill) { return o0 - o0 * moved / toFill }
        return o1 * (moved - toFill) / (whole - toFill)
    }

    /// The viewport point that stays still, per axis: (o1 − r·o0) / (1 − r). `nil` when the zoom
    /// doesn't change and the view only pans.
    var anchor: CGPoint? {
        let r = to.zoom / from.zoom
        guard r != 1 else { return nil }
        return CGPoint(x: (to.offset.x - r * from.offset.x) / (1 - r), y: (to.offset.y - r * from.offset.y) / (1 - r))
    }
}
