import CoreGraphics

/// The Viewer's zoom and pan. All sizes and points are drawable pixels, y down (docs/design.md §3).
///
/// Nothing here changes on its own (docs/product.md, "Nothing moves unless you move it"): resizing
/// the window or the Capture Area keeps the zoom and the visible pixels in place. Fit is a command,
/// applied once to the first frame and then only when asked for.
@MainActor
final class ZoomPanController {
    private(set) var state = ZoomPanState(contentSize: .zero, viewportSize: .zero)
    var onChange: (() -> Void)?

    /// Whether the current zoom is the Fit zoom, for the toolbar.
    var isFit: Bool { state.isFit }

    private var hasContent: Bool { state.contentSize.width > 0 && state.contentSize.height > 0 }

    func setViewport(_ size: CGSize) {
        guard size != state.viewportSize else { return }
        let first = state.viewportSize == .zero
        state.viewportSize = size
        state = first && hasContent ? state.fitted() : state.clamped()
        onChange?()
    }

    /// The whole Capture Area, `size` source pixels, whose top-left corner moved by `originShift`
    /// source pixels since the last frame (non-zero when its left or top edge was dragged).
    func setContent(_ size: CGSize, originShift: CGPoint = .zero) {
        guard size != state.contentSize else { return }
        if hasContent {
            state = state.resizingContent(to: size, originShift: originShift)
        } else {
            state.contentSize = size
            state = state.fitted()
        }
        onChange?()
    }

    func fit() {
        state = state.fitted()
        onChange?()
    }

    /// Zooms around `anchor` (a viewport point), or around the viewport centre.
    func setZoom(_ zoom: CGFloat, around anchor: CGPoint? = nil) {
        let center = CGPoint(x: state.viewportSize.width / 2, y: state.viewportSize.height / 2)
        state = state.zoomed(to: zoom, around: anchor ?? center)
        onChange?()
    }

    func stepZoom(_ direction: Int, around anchor: CGPoint? = nil) {
        setZoom(state.steppedZoom(direction: direction), around: anchor)
    }

    func pan(by delta: CGPoint) {
        let next = state.panned(by: delta)
        guard next != state else { return }
        state = next
        onChange?()
    }

}
