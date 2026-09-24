import CoreGraphics

/// Placement of the captured image inside the Viewer.
///
/// Everything is in device pixels with a top-left origin, y down: source pixels of the captured
/// image, and drawable pixels of the Viewer. `zoom` is drawable pixels per source pixel, so 8 means
/// every source pixel covers exactly 8×8 drawable pixels (docs/design.md §3).
struct ZoomPanState: Equatable, Sendable {
    static let presets: [CGFloat] = [1, 2, 4, 8, 16]
    /// Steps for `+`/`-` and for snapping keyboard zoom.
    static let ladder: [CGFloat] = [0.125, 0.25, 0.5, 1, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 64]
    static let zoomRange: ClosedRange<CGFloat> = 0.05...64

    var zoom: CGFloat
    /// Where source pixel (0, 0) lands in the viewport. Whole pixels, so pixel edges stay crisp.
    var offset: CGPoint
    var contentSize: CGSize
    var viewportSize: CGSize

    init(zoom: CGFloat = 1, offset: CGPoint = .zero, contentSize: CGSize, viewportSize: CGSize) {
        self.zoom = zoom
        self.offset = offset
        self.contentSize = contentSize
        self.viewportSize = viewportSize
    }

    var scaledContentSize: CGSize {
        CGSize(width: contentSize.width * zoom, height: contentSize.height * zoom)
    }

    // MARK: Mapping

    func sourcePoint(forViewportPoint p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - offset.x) / zoom, y: (p.y - offset.y) / zoom)
    }

    func viewportPoint(forSourcePoint s: CGPoint) -> CGPoint {
        CGPoint(x: s.x * zoom + offset.x, y: s.y * zoom + offset.y)
    }

    /// Where a captured image of `size` source pixels, placed at `origin` inside the Capture Area,
    /// lands in the viewport. Both the Viewer and Copy View use this, so a copy matches the screen.
    func imageRect(origin: CGPoint, size: CGSize) -> CGRect {
        let topLeft = viewportPoint(forSourcePoint: origin)
        return CGRect(x: topLeft.x, y: topLeft.y, width: size.width * zoom, height: size.height * zoom)
    }

    /// The whole source pixel under a viewport point, or `nil` outside the image.
    func sourcePixel(atViewportPoint p: CGPoint) -> (x: Int, y: Int)? {
        let s = sourcePoint(forViewportPoint: p)
        let x = Int(s.x.rounded(.down))
        let y = Int(s.y.rounded(.down))
        guard x >= 0, y >= 0, x < Int(contentSize.width), y < Int(contentSize.height) else { return nil }
        return (x, y)
    }

    // MARK: Operations

    /// Zoom that fits the whole image into the viewport.
    var fitZoom: CGFloat {
        guard contentSize.width > 0, contentSize.height > 0 else { return 1 }
        let fit = min(viewportSize.width / contentSize.width, viewportSize.height / contentSize.height)
        return min(max(fit, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
    }

    /// Changes the zoom keeping the source point under `anchor` (a viewport point) in place.
    func zoomed(to newZoom: CGFloat, around anchor: CGPoint) -> ZoomPanState {
        let target = min(max(newZoom, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        var next = self
        next.offset = CGPoint(
            x: anchor.x - (anchor.x - offset.x) * target / zoom,
            y: anchor.y - (anchor.y - offset.y) * target / zoom
        )
        next.zoom = target
        return next.clamped()
    }

    /// The next ladder step above (`direction > 0`) or below the current zoom.
    func steppedZoom(direction: Int) -> CGFloat {
        if direction > 0 {
            return Self.ladder.first { $0 > zoom + 0.0001 } ?? Self.zoomRange.upperBound
        }
        return Self.ladder.last { $0 < zoom - 0.0001 } ?? Self.zoomRange.lowerBound
    }

    func panned(by delta: CGPoint) -> ZoomPanState {
        var next = self
        next.offset = CGPoint(x: offset.x + delta.x, y: offset.y + delta.y)
        return next.clamped()
    }

    /// Keeps the image in view: an image smaller than the viewport is centred on that axis, a larger
    /// one can't be panned past its edges. The offset is rounded to whole pixels.
    func clamped() -> ZoomPanState {
        var next = self
        next.offset = CGPoint(
            x: Self.clampAxis(offset.x, content: scaledContentSize.width, viewport: viewportSize.width),
            y: Self.clampAxis(offset.y, content: scaledContentSize.height, viewport: viewportSize.height)
        )
        return next
    }

    private static func clampAxis(_ offset: CGFloat, content: CGFloat, viewport: CGFloat) -> CGFloat {
        if content <= viewport {
            return ((viewport - content) / 2).rounded(.down)
        }
        return min(0, max(viewport - content, offset)).rounded()
    }
}
