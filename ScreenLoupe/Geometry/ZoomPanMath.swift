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
    /// Zooms closer than this are the same zoom: a preset, a ladder step or Fit reached through
    /// float arithmetic.
    static let sameZoom: CGFloat = 0.0001
    /// A float step: an edge this close to a pixel boundary, or a slack this small, is on it.
    static let floatStep: CGFloat = 1e-6

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

    /// The part of the image the viewport shows, in source pixels, clipped to the image; fractional at
    /// the edges, where a pixel shows only in part. `nil` when the viewport shows the whole image, or
    /// none of it. An edge a float step short of the image's edge reaches it: at Fit, viewport ÷ zoom
    /// can come out just under the image's size.
    var visibleSourceRect: CGRect? {
        let tolerance = Self.floatStep
        let topLeft = sourcePoint(forViewportPoint: .zero)
        let bottomRight = sourcePoint(forViewportPoint: CGPoint(x: viewportSize.width, y: viewportSize.height))
        let minX = topLeft.x < tolerance ? 0 : topLeft.x
        let minY = topLeft.y < tolerance ? 0 : topLeft.y
        let maxX = bottomRight.x > contentSize.width - tolerance ? contentSize.width : bottomRight.x
        let maxY = bottomRight.y > contentSize.height - tolerance ? contentSize.height : bottomRight.y
        let visible = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        guard visible.width > 0, visible.height > 0, visible != CGRect(origin: .zero, size: contentSize) else {
            return nil
        }
        return visible
    }

    /// The view of just `sourceRect` (whole source pixels) at the current zoom: a viewport its size,
    /// with its top-left corner at the viewport's. For copying the Select tool's selection, which may
    /// reach beyond the visible viewport.
    func cropped(to sourceRect: CGRect) -> ZoomPanState {
        var next = self
        next.viewportSize = CGSize(
            width: (sourceRect.width * zoom).rounded(), height: (sourceRect.height * zoom).rounded())
        next.offset = CGPoint(x: (-sourceRect.minX * zoom).rounded(), y: (-sourceRect.minY * zoom).rounded())
        return next
    }

    // MARK: Operations

    /// Whether the zoom is the one that fits the whole image, as the Fit preset does.
    var isFit: Bool {
        abs(zoom - fitZoom) < Self.sameZoom
    }

    /// Zoom that fits the whole image into the viewport.
    var fitZoom: CGFloat {
        guard contentSize.width > 0, contentSize.height > 0 else { return 1 }
        let fit = min(viewportSize.width / contentSize.width, viewportSize.height / contentSize.height)
        return Self.clampedZoom(fit)
    }

    /// `zoom` kept within `zoomRange`.
    static func clampedZoom(_ zoom: CGFloat) -> CGFloat {
        min(max(zoom, zoomRange.lowerBound), zoomRange.upperBound)
    }

    /// The centre of the part of the image the viewport shows: the image's own centre when it shows
    /// whole, the viewport's when the image covers it, on each axis apart. The viewport's centre when
    /// no part of the image shows (no image, or no viewport yet).
    var visibleImageCenter: CGPoint {
        let image = CGRect(origin: offset, size: scaledContentSize)
        let visible = image.intersection(CGRect(origin: .zero, size: viewportSize))
        guard !visible.isEmpty else { return CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2) }
        return CGPoint(x: visible.midX, y: visible.midY)
    }

    /// A zoom around the pointer (a wheel, a pinch, `+`/`-` over the Viewer): the source point under
    /// `anchor` (a viewport point) stays in place, and the image is only kept in view as any pan is.
    func zoomed(to newZoom: CGFloat, around anchor: CGPoint) -> ZoomPanState {
        let target = Self.clampedZoom(newZoom)
        var next = self
        next.offset = CGPoint(
            x: anchor.x - (anchor.x - offset.x) * target / zoom,
            y: anchor.y - (anchor.y - offset.y) * target / zoom
        )
        next.zoom = target
        return next.clamped()
    }

    /// A zoom without a pointer (a preset, a typed zoom, `+`/`-` with the pointer elsewhere): the
    /// source point at the centre of the part of the image that shows is brought to the viewport's
    /// centre, so a small image dragged to one side shows its own middle in the middle of the Viewer.
    /// On an axis where the image comes out no larger than the viewport it is then centred; on a
    /// larger one it is kept against the edges as any pan is, which can stop that point short of the
    /// centre. An image that covers the viewport shows its centre there already: a zoom around it.
    func zoomedAboutImage(to newZoom: CGFloat) -> ZoomPanState {
        let target = Self.clampedZoom(newZoom)
        let anchor = visibleImageCenter
        let center = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        var next = self
        next.offset = CGPoint(
            x: center.x - (anchor.x - offset.x) * target / zoom,
            y: center.y - (anchor.y - offset.y) * target / zoom
        )
        next.zoom = target
        next = next.clamped()
        let scaled = next.scaledContentSize
        if scaled.width <= viewportSize.width {
            next.offset.x = Self.centeredAxis(content: scaled.width, viewport: viewportSize.width)
        }
        if scaled.height <= viewportSize.height {
            next.offset.y = Self.centeredAxis(content: scaled.height, viewport: viewportSize.height)
        }
        return next
    }

    /// The next ladder step above (`direction > 0`) or below the current zoom.
    func steppedZoom(direction: Int) -> CGFloat {
        if direction > 0 {
            return Self.ladder.first { $0 > zoom + Self.sameZoom } ?? Self.zoomRange.upperBound
        }
        return Self.ladder.last { $0 < zoom - Self.sameZoom } ?? Self.zoomRange.lowerBound
    }

    /// Fit: the zoom that shows the whole image, centred.
    func fitted() -> ZoomPanState {
        var next = self
        next.zoom = fitZoom
        return next.centered()
    }

    /// The image centred on both axes. Only on request (Fit, the first frame, and a zoom without a
    /// pointer on an axis where the image is no larger than the viewport): centring on a resize or a
    /// pan would move the image by itself (docs/product.md, "Nothing moves unless you move it").
    func centered() -> ZoomPanState {
        var next = self
        next.offset = CGPoint(
            x: Self.centeredAxis(content: scaledContentSize.width, viewport: viewportSize.width),
            y: Self.centeredAxis(content: scaledContentSize.height, viewport: viewportSize.height)
        )
        return next
    }

    /// A fitted image can come out a float step larger than the viewport on its fitting axis; that is
    /// no slack at all, not a pixel to shift it by. A larger image, at a restored zoom, still centres
    /// past the edges.
    private static func centeredAxis(content: CGFloat, viewport: CGFloat) -> CGFloat {
        let slack = viewport - content
        return (abs(slack) < floatStep ? 0 : slack / 2).rounded(.down)
    }

    /// The Capture Area was resized to `size` and its top-left corner moved by `originShift` source
    /// pixels. The zoom stays, and so do the pixels that were already visible: dragging the right or
    /// bottom edge reveals more to the right or below, dragging the left or top edge reveals more to
    /// the left or above, and nothing already on screen shifts.
    func resizingContent(to size: CGSize, originShift: CGPoint) -> ZoomPanState {
        var next = self
        next.contentSize = size
        next.offset = CGPoint(x: offset.x + originShift.x * zoom, y: offset.y + originShift.y * zoom)
        return next.clamped()
    }

    /// The part the viewport shows moved by `delta` source pixels: dragging its outline on the Capture
    /// Area. On an axis where the whole image shows there is no part to move, and the image stays.
    /// Clamped as any pan is.
    func movingVisiblePart(by delta: CGPoint) -> ZoomPanState {
        var next = self
        if scaledContentSize.width > viewportSize.width { next.offset.x -= delta.x * zoom }
        if scaledContentSize.height > viewportSize.height { next.offset.y -= delta.y * zoom }
        return next.clamped()
    }

    func panned(by delta: CGPoint) -> ZoomPanState {
        var next = self
        next.offset = CGPoint(x: offset.x + delta.x, y: offset.y + delta.y)
        return next.clamped()
    }

    /// Keeps the image in view without moving it more than needed: an image smaller than the viewport
    /// stays wholly inside it, a larger one can't be panned past its edges. The offset is rounded to
    /// whole pixels, unless `toWholePixels` is false (a zoom glide's presented view, whose offset is
    /// fractional as its zoom is).
    func clamped(toWholePixels: Bool = true) -> ZoomPanState {
        var next = self
        next.offset = CGPoint(
            x: Self.clampAxis(
                offset.x, content: scaledContentSize.width, viewport: viewportSize.width, toWholePixels: toWholePixels),
            y: Self.clampAxis(
                offset.y, content: scaledContentSize.height, viewport: viewportSize.height, toWholePixels: toWholePixels
            )
        )
        return next
    }

    private static func clampAxis(
        _ offset: CGFloat, content: CGFloat, viewport: CGFloat, toWholePixels: Bool
    )
        -> CGFloat
    {
        if content <= viewport {
            let limited = min(max(offset, 0), viewport - content)
            return toWholePixels ? limited.rounded(.down) : limited
        }
        let limited = min(0, max(viewport - content, offset))
        return toWholePixels ? limited.rounded() : limited
    }
}
