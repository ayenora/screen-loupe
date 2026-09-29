import AppKit
import QuartzCore

/// The Viewer's zoom and pan. All sizes and points are drawable pixels, y down (docs/design.md §3).
///
/// Nothing here changes on its own (docs/product.md, "Nothing moves unless you move it"): resizing
/// the window or the Capture Area keeps the zoom and the visible pixels in place. Fit is a command,
/// applied once to the first frame and then only when asked for.
///
/// `state` is the model: what is kept, copied, snapshotted and shown in the toolbar. A zoom command
/// (Fit, a preset, a typed zoom, `+`/`-`) sets it at once and the Viewer glides to it over
/// `ZoomAnimation.duration`: what it draws, and what the pointer points at, is `presented`.
/// Continuous input (wheel, pinch, drag) and a change of what shows take over from the presented
/// view (`settle`), without a jump.
@MainActor
final class ZoomPanController {
    private(set) var state = ZoomPanState(contentSize: .zero, viewportSize: .zero)
    private var observers: [() -> Void] = []
    private var presentedObservers: [() -> Void] = []
    private var animation: ZoomAnimation?

    /// Called when a glide starts, to drive redraws until `animationFrame()` says it is over.
    var onAnimationStart: (() -> Void)?

    /// Calls `observer` after every change of the zoom or the pan.
    func observe(_ observer: @escaping () -> Void) {
        observers.append(observer)
    }

    /// Calls `observer` after every change of `presented`: each change of the model, and each frame
    /// of a glide.
    func observePresented(_ observer: @escaping () -> Void) {
        presentedObservers.append(observer)
    }

    private func changed() {
        observers.forEach { $0() }
        presentedObservers.forEach { $0() }
    }

    private static func now() -> TimeInterval { CACurrentMediaTime() }

    /// The view as drawn now: the model, or on its way there during a glide.
    var presented: ZoomPanState {
        animation?.state(at: Self.now()) ?? state
    }

    /// A frame of the glide: tells the observers of `presented`. Returns whether it goes on.
    func animationFrame() -> Bool {
        guard let animation else { return false }
        let isOver = animation.isFinished(at: Self.now())
        if isOver { self.animation = nil }
        presentedObservers.forEach { $0() }
        return !isOver
    }

    /// Stops a glide where it shows now and makes that the model, on whole pixels as any pan is, for
    /// input that goes on from what is on screen: a wheel, a pinch, a drag, a press of a tool.
    func settle() {
        guard let animation else { return }
        self.animation = nil
        let shown = animation.state(at: Self.now()).clamped()
        guard shown != state else { return }
        state = shown
        changed()
    }

    /// A resize mid-glide: the glide ends at its target, the model, and the resize applies to that as
    /// it does outside a glide (a glide to Fit ends at Fit for the old size, and the resize keeps that
    /// zoom). Stopping where it shows would leave a zoom no command asked for.
    private func endGlide() {
        animation = nil
    }

    /// A zoom command: the model becomes `target` at once; the view glides there from where it shows
    /// now, unless Reduce Motion is on or there is nothing shown yet. `throughFill`: a zoom about the
    /// image (`ZoomAnimation.throughFill`).
    private func command(_ target: ZoomPanState, throughFill: Bool = false) {
        let from = presented
        state = target
        let glides =
            from != target && hasContent && state.viewportSize != .zero
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        animation = glides ? ZoomAnimation(from: from, to: target, start: Self.now(), throughFill: throughFill) : nil
        if glides { onAnimationStart?() }
        changed()
    }

    /// Whether the current zoom is the Fit zoom, for the toolbar.
    var isFit: Bool { state.isFit }

    /// The zoom kept from the last session (docs/product.md, Kept between launches), applied to the first frame instead of Fit.
    var restoredZoom: CGFloat?

    private var hasContent: Bool { state.contentSize.width > 0 && state.contentSize.height > 0 }

    /// Fit once the viewport is known, instead of the restored zoom: an opened image in a Viewer not
    /// laid out yet.
    private var fitsFirstViewport = false

    func setViewport(_ size: CGSize) {
        guard size != state.viewportSize else { return }
        endGlide()
        let first = state.viewportSize == .zero
        state.viewportSize = size
        state = first && hasContent ? initialState() : state.clamped()
        if first { fitsFirstViewport = false }
        changed()
    }

    /// The whole Capture Area, `size` source pixels, whose top-left corner moved by `originShift`
    /// source pixels since the last frame (non-zero when its left or top edge was dragged).
    func setContent(_ size: CGSize, originShift: CGPoint = .zero) {
        guard size != state.contentSize else { return }
        endGlide()
        if hasContent {
            state = state.resizingContent(to: size, originShift: originShift)
        } else {
            state.contentSize = size
            state = initialState()
        }
        changed()
    }

    /// The first frame: the restored zoom, centred, or Fit.
    private func initialState() -> ZoomPanState {
        guard !fitsFirstViewport, let restoredZoom, state.viewportSize != .zero else { return state.fitted() }
        var next = state
        next.zoom = ZoomPanState.clampedZoom(restoredZoom)
        return next.centered()
    }

    /// The Fit command: glides.
    func fit() {
        command(state.fitted())
    }

    /// Fit for a picture that opens fitted (docs/product.md, Open Image): now, at once, and once more
    /// when the viewport is first known, if it isn't yet.
    func fitWhenShown() {
        fitsFirstViewport = state.viewportSize == .zero
        animation = nil
        state = state.fitted()
        changed()
    }

    /// A zoom command (a preset, a typed zoom, `+`/`-`): glides to `zoom`. Around `anchor`, the
    /// pointer (a viewport point), keeping the source point under it where it shows now; without one,
    /// bringing the centre of the part of the image that shows to the viewport's centre, centring the
    /// image on an axis where it comes out no larger than the viewport
    /// (`ZoomPanState.zoomedAboutImage`).
    func setZoom(_ zoom: CGFloat, around anchor: CGPoint? = nil) {
        if let anchor {
            command(presented.zoomed(to: zoom, around: anchor))
        } else {
            command(presented.zoomedAboutImage(to: zoom), throughFill: true)
        }
    }

    /// `+`/`-`: the next ladder step from the zoom asked for last, so quick presses add up.
    func stepZoom(_ direction: Int, around anchor: CGPoint? = nil) {
        setZoom(state.steppedZoom(direction: direction), around: anchor)
    }

    /// Continuous zoom (wheel, pinch) by `factor` around `anchor`, at once, from the view as shown.
    func zoom(by factor: CGFloat, around anchor: CGPoint) {
        settle()
        state = state.zoomed(to: state.zoom * factor, around: anchor)
        changed()
    }

    /// Back to a zoom and pan kept earlier: a recent capture as it was left, or the live view after
    /// one. Kept inside the image as any pan is. At once: another picture shows.
    func restore(zoom: CGFloat, offset: CGPoint) {
        fitsFirstViewport = false
        animation = nil
        var next = state
        next.zoom = zoom
        next.offset = offset
        state = next.clamped()
        changed()
    }

    func pan(by delta: CGPoint) {
        settle()
        let next = state.panned(by: delta)
        guard next != state else { return }
        state = next
        changed()
    }

}
