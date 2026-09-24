import CoreGraphics

/// The Viewer window frame that shows the whole magnified Capture Area without panning, as far as
/// the screen allows. All rects are AppKit global points, y up.
enum ViewerWindowFit {
    /// - Parameters:
    ///   - imageSize: the magnified Capture Area, in points.
    ///   - chrome: what the window adds around the image: title bar, toolbar, the Color Meter.
    ///   - window: the window's current frame. Its top-left corner stays put when the new frame fits
    ///     there; otherwise the window moves just enough to stay on screen.
    ///   - visible: the screen's visible frame (without the menu bar and the Dock). The window is
    ///     never larger than this; a bigger image is then panned as before.
    ///   - minSize: the window's minimum size.
    ///   - scale: the backing scale, so the image area ends on a whole device pixel.
    static func frame(
        imageSize: CGSize, chrome: CGSize, window: CGRect, visible: CGRect, minSize: CGSize, scale: CGFloat
    ) -> CGRect {
        func fitted(_ image: CGFloat, _ chrome: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
            let wanted = (image * scale).rounded(.up) / scale + chrome
            return Swift.min(Swift.max(wanted, minimum), maximum)
        }
        let width = fitted(imageSize.width, chrome.width, min: minSize.width, max: visible.width)
        let height = fitted(imageSize.height, chrome.height, min: minSize.height, max: visible.height)
        let x = Swift.min(Swift.max(window.minX, visible.minX), visible.maxX - width)
        let top = Swift.max(Swift.min(window.maxY, visible.maxY), visible.minY + height)
        return CGRect(x: x, y: top - height, width: width, height: height)
    }
}
