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
struct ZoomAnimation: Equatable, Sendable {
    static let duration: TimeInterval = 0.2

    let from: ZoomPanState
    let to: ZoomPanState
    /// Seconds on the clock `state(at:)` is given.
    let start: TimeInterval
    let duration: TimeInterval

    init(from: ZoomPanState, to: ZoomPanState, start: TimeInterval, duration: TimeInterval = Self.duration) {
        self.from = from
        self.to = to
        self.start = start
        self.duration = duration
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
        // (1 − r^e) / (1 − r) with expm1 for precision when r is close to 1.
        let weight = logRatio == 0 ? e : expm1(e * logRatio) / expm1(logRatio)
        var next = to
        next.zoom = from.zoom * exp(e * logRatio)
        next.offset = CGPoint(
            x: from.offset.x + (to.offset.x - from.offset.x) * weight,
            y: from.offset.y + (to.offset.y - from.offset.y) * weight)
        return next.clamped(toWholePixels: false)
    }

    /// The viewport point that stays still, per axis: (o1 − r·o0) / (1 − r). `nil` when the zoom
    /// doesn't change and the view only pans.
    var anchor: CGPoint? {
        let r = to.zoom / from.zoom
        guard r != 1 else { return nil }
        return CGPoint(x: (to.offset.x - r * from.offset.x) / (1 - r), y: (to.offset.y - r * from.offset.y) / (1 - r))
    }

    /// A new command at `time`: a glide to `target` from wherever this one shows then, so nothing
    /// jumps.
    func retargeted(to target: ZoomPanState, at time: TimeInterval) -> ZoomAnimation {
        ZoomAnimation(from: state(at: time), to: target, start: time, duration: duration)
    }
}
