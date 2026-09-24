import CoreGraphics

/// Where a Capture Area is captured from, and how the captured image sits inside the area.
struct CaptureGeometry: Equatable, Sendable {
    /// The display the stream captures: the one holding the larger share of the area.
    var display: DisplayInfo
    /// The part of the area on that display, in display-local points, for `sourceRect`.
    var sourceRect: DisplayLocalRect
    /// Output size of the captured image, for `SCStreamConfiguration.width`/`height`.
    var outputSize: PixelSize
    /// Size of the whole area in pixels of the capturing display.
    var areaSize: PixelSize
    /// Top-left corner of the captured image inside the whole area, in pixels. Non-zero only when
    /// the area straddles two displays and part of it lies on the other one.
    var imageOrigin: CGPoint
}

extension CaptureGeometry {
    /// The whole area's top-left corner in pixels of its display, from the display's top-left.
    var areaOrigin: CGPoint {
        let scale = display.scale
        return CGPoint(
            x: (sourceRect.rect.minX * scale).rounded() - imageOrigin.x,
            y: (sourceRect.rect.minY * scale).rounded() - imageOrigin.y)
    }

    /// Where the captured image goes in an image of the whole area, in that image's pixels with
    /// CoreGraphics' bottom-left origin (Copy Source).
    var imageRectInAreaImage: CGRect {
        CGRect(
            x: imageOrigin.x, y: CGFloat(areaSize.height) - imageOrigin.y - CGFloat(outputSize.height),
            width: CGFloat(outputSize.width), height: CGFloat(outputSize.height))
    }
}

/// Tells a Capture Area resized by its left or top edge from one that moved, frame to frame, so the
/// Viewer keeps showing the same pixels (docs/product.md, "Nothing moves unless you move it").
struct AreaResizeTracker {
    private var last: (display: CGDirectDisplayID, origin: CGPoint, size: PixelSize)?

    /// After a freeze the area may have moved and been resized in one go; the next frame then keeps
    /// the framing, as for a move, instead of taking the whole move for an edge drag.
    mutating func forget() {
        last = nil
    }

    /// How far the area's top-left corner moved, in source pixels, if it was resized: non-zero when
    /// the left or top edge was dragged. Zero for a move (the Viewer keeps its framing and shows the
    /// new place) and across displays.
    mutating func originShift(for geometry: CaptureGeometry) -> CGPoint {
        let origin = geometry.areaOrigin
        defer { last = (geometry.display.id, origin, geometry.areaSize) }
        guard let last, last.display == geometry.display.id, last.size != geometry.areaSize else { return .zero }
        return CGPoint(x: origin.x - last.origin.x, y: origin.y - last.origin.y)
    }
}

/// All conversions between the global, Quartz, display-local and pixel coordinate systems.
struct DisplayCoordinateConverter: Sendable {
    let layout: DisplayLayout

    init(layout: DisplayLayout) {
        self.layout = layout
    }

    // MARK: Global ↔ Quartz

    func quartzRect(_ global: GlobalRect) -> QuartzRect {
        let r = global.rect
        let primaryHeight = layout.primary.globalFrame.height
        return QuartzRect(rect: CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height))
    }

    func globalRect(_ quartz: QuartzRect) -> GlobalRect {
        let r = quartz.rect
        let primaryHeight = layout.primary.globalFrame.height
        return GlobalRect(rect: CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height))
    }

    // MARK: Displays

    /// The display holding the largest part of `global`, or `nil` when the rect is on no display.
    func owningDisplay(for global: GlobalRect) -> DisplayInfo? {
        var best: (display: DisplayInfo, area: CGFloat)?
        for display in layout.displays {
            let overlap = display.globalFrame.intersection(global.rect)
            guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { continue }
            let area = overlap.width * overlap.height
            if area > (best?.area ?? 0) {
                best = (display, area)
            }
        }
        return best?.display
    }

    /// `global` in points relative to the top-left corner of `display`. Not clipped to the display.
    func displayLocalRect(_ global: GlobalRect, on display: DisplayInfo) -> DisplayLocalRect {
        let rect = quartzRect(global).rect
        let displayOrigin = quartzRect(GlobalRect(rect: display.globalFrame)).rect.origin
        return DisplayLocalRect(
            displayID: display.id,
            rect: rect.offsetBy(dx: -displayOrigin.x, dy: -displayOrigin.y)
        )
    }

    // MARK: Pixel grid

    /// Snaps `global` to the pixel grid of the display that owns it, so the capture is never
    /// resampled. Origin and size are rounded independently: moving the area never changes its size.
    func snapped(_ global: GlobalRect) -> GlobalRect {
        guard let display = owningDisplay(for: global) else { return global }
        let scale = display.scale
        let r = global.rect
        return GlobalRect(
            rect: CGRect(
                x: (r.minX * scale).rounded() / scale,
                y: (r.minY * scale).rounded() / scale,
                width: (r.width * scale).rounded() / scale,
                height: (r.height * scale).rounded() / scale
            )
        )
    }

    /// Snaps each edge of `global` to the pixel grid on its own. Used while resizing: the edges that
    /// don't move are already on the grid and stay exactly where they are.
    func snappedEdges(_ global: GlobalRect) -> GlobalRect {
        guard let display = owningDisplay(for: global) else { return global }
        let scale = display.scale
        let r = global.rect
        let minX = (r.minX * scale).rounded() / scale
        let minY = (r.minY * scale).rounded() / scale
        let maxX = (r.maxX * scale).rounded() / scale
        let maxY = (r.maxY * scale).rounded() / scale
        return GlobalRect(rect: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
    }

    func pixelSize(of size: CGSize, scale: CGFloat) -> PixelSize {
        PixelSize(width: Int((size.width * scale).rounded()), height: Int((size.height * scale).rounded()))
    }

    // MARK: Cursor

    /// The pixel of the Capture Area under a global point, counted from the area's top-left corner in
    /// pixels of its display; `nil` outside the area.
    static func areaPixel(at point: CGPoint, inArea area: CGRect, scale: CGFloat) -> (x: Int, y: Int)? {
        guard area.contains(point) else { return nil }
        // Global coordinates are y up; area pixels are y down from the top edge.
        let x = Int(((point.x - area.minX) * scale).rounded(.down))
        let y = Int(((area.maxY - point.y) * scale).rounded(.down))
        let width = Int((area.width * scale).rounded())
        let height = Int((area.height * scale).rounded())
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        return (x, y)
    }

    // MARK: Capture

    /// What to capture for a Capture Area. `nil` when the area is on no display.
    func captureGeometry(for area: GlobalRect) -> CaptureGeometry? {
        guard let display = owningDisplay(for: area) else { return nil }
        let visible = GlobalRect(rect: area.rect.intersection(display.globalFrame))
        let whole = displayLocalRect(area, on: display)
        let source = displayLocalRect(visible, on: display)
        let scale = display.scale
        return CaptureGeometry(
            display: display,
            sourceRect: source,
            outputSize: pixelSize(of: source.rect.size, scale: scale),
            areaSize: pixelSize(of: whole.rect.size, scale: scale),
            imageOrigin: CGPoint(
                x: ((source.rect.minX - whole.rect.minX) * scale).rounded(),
                y: ((source.rect.minY - whole.rect.minY) * scale).rounded()
            )
        )
    }
}
