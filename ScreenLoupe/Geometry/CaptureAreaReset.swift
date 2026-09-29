import CoreGraphics

/// Reset Capture Area (docs/product.md, Capture Area): the area back to the size it has on first
/// launch, centred on a display.
enum CaptureAreaReset {
    /// The Capture Area's size on first launch and after a reset, in points.
    static let defaultSize = CGSize(width: 320, height: 200)

    /// `size`, no larger than `visibleFrame`, centred on it, in AppKit global coordinates. Each edge
    /// lies on the pixel grid of a display with `scale` pixels per point.
    static func rect(centredIn visibleFrame: CGRect, scale: CGFloat, size: CGSize = defaultSize) -> CGRect {
        let onGrid = { (value: CGFloat) in (value * scale).rounded() / scale }
        // Whole pixels that fit: a display smaller than the size gets its whole visible frame.
        let width = min((size.width * scale).rounded(), (visibleFrame.width * scale).rounded(.down)) / scale
        let height = min((size.height * scale).rounded(), (visibleFrame.height * scale).rounded(.down)) / scale
        return CGRect(
            x: onGrid(visibleFrame.midX - width / 2), y: onGrid(visibleFrame.midY - height / 2), width: width,
            height: height)
    }
}
