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
