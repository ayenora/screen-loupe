import CoreGraphics

/// The Viewer's zoom and pan. All sizes and points are drawable pixels, y down (docs/design.md §3).
///
/// Nothing here changes on its own (docs/product.md, "Nothing moves unless you move it"): resizing
/// the window or the Capture Area keeps the zoom and the visible pixels in place. Fit is a command,
/// applied once to the first frame and then only when asked for.
@MainActor
final class ZoomPanController {
    private(set) var state = ZoomPanState(contentSize: .zero, viewportSize: .zero)
    private var observers: [() -> Void] = []

    /// Calls `observer` after every change of the zoom or the pan.
    func observe(_ observer: @escaping () -> Void) {
        observers.append(observer)
    }

    private func changed() {
        observers.forEach { $0() }
    }

    /// Whether the current zoom is the Fit zoom, for the toolbar.
    var isFit: Bool { state.isFit }

    /// The zoom kept from the last session (docs/product.md, Kept between launches), applied to the first frame instead of Fit.
    var restoredZoom: CGFloat?

    private var hasContent: Bool { state.contentSize.width > 0 && state.contentSize.height > 0 }

    func setViewport(_ size: CGSize) {
        guard size != state.viewportSize else { return }
        let first = state.viewportSize == .zero
        state.viewportSize = size
        state = first && hasContent ? initialState() : state.clamped()
        changed()
    }

    /// The whole Capture Area, `size` source pixels, whose top-left corner moved by `originShift`
    /// source pixels since the last frame (non-zero when its left or top edge was dragged).
    func setContent(_ size: CGSize, originShift: CGPoint = .zero) {
        guard size != state.contentSize else { return }
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
        guard let restoredZoom, state.viewportSize != .zero else { return state.fitted() }
        var next = state
        next.zoom = min(max(restoredZoom, ZoomPanState.zoomRange.lowerBound), ZoomPanState.zoomRange.upperBound)
        return next.centered()
    }

    func fit() {
        state = state.fitted()
        changed()
    }

    /// Zooms around `anchor` (a viewport point), or around the viewport centre.
    func setZoom(_ zoom: CGFloat, around anchor: CGPoint? = nil) {
        let center = CGPoint(x: state.viewportSize.width / 2, y: state.viewportSize.height / 2)
        state = state.zoomed(to: zoom, around: anchor ?? center)
        changed()
    }

    func stepZoom(_ direction: Int, around anchor: CGPoint? = nil) {
        setZoom(state.steppedZoom(direction: direction), around: anchor)
    }

    func pan(by delta: CGPoint) {
        let next = state.panned(by: delta)
        guard next != state else { return }
        state = next
        changed()
    }

}
