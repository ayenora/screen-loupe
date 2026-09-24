import CoreGraphics

/// The Viewer's zoom and pan. All sizes and points are drawable pixels, y down (docs/design.md §3).
@MainActor
final class ZoomPanController {
    private(set) var state = ZoomPanState(contentSize: .zero, viewportSize: .zero)
    /// Fit follows the viewport and the content; any explicit zoom leaves it.
    private(set) var isFit = true
    var onChange: (() -> Void)?

    func setViewport(_ size: CGSize) {
        guard size != state.viewportSize else { return }
        state.viewportSize = size
        settle()
    }

    /// The size of the whole Capture Area in source pixels.
    func setContent(_ size: CGSize) {
        guard size != state.contentSize else { return }
        state.contentSize = size
        settle()
    }

    func fit() {
        isFit = true
        settle()
    }

    /// Zooms around `anchor` (a viewport point), or around the viewport centre.
    func setZoom(_ zoom: CGFloat, around anchor: CGPoint? = nil) {
        isFit = false
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

    private func settle() {
        if isFit {
            state.zoom = state.fitZoom
        }
        state = state.clamped()
        onChange?()
    }
}
