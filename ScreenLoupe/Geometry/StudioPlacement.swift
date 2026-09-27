import CoreGraphics

/// Where the Screenshot studio's frame and palette go when nothing is kept for them
/// (docs/product.md, Screenshot studio). AppKit global coordinates, y up.
enum StudioPlacement {
    /// The frame's size the first time, shrunk to fit its display.
    static let defaultFrameSize = CGSize(width: 1440, height: 900)
    /// Between the frame's rect and the palette: wider than the frame's hover zone
    /// (`OverlayMetrics.hoverReach`), so the pointer on the palette never reveals the frame's handles.
    static let paletteGap: CGFloat = 32
    /// Kept free at the display's edges.
    static let screenMargin: CGFloat = 8
    /// Kept free above and below the frame, for its tab and size label.
    static let verticalRoom: CGFloat = 40

    /// The frame the first time: `defaultFrameSize` centred on `visibleFrame`, shrunk so its tab and
    /// label and a palette `paletteWidth` wide beside it still fit on the display. Whole points.
    static func defaultFrame(in visibleFrame: CGRect, paletteWidth: CGFloat) -> CGRect {
        let side = paletteWidth + 2 * paletteGap + screenMargin
        let width = min(defaultFrameSize.width, visibleFrame.width - 2 * side)
        let height = min(defaultFrameSize.height, visibleFrame.height - 2 * verticalRoom)
        let size = CGSize(width: max(width, 0).rounded(.down), height: max(height, 0).rounded(.down))
        return CGRect(
            x: (visibleFrame.midX - size.width / 2).rounded(.down),
            y: (visibleFrame.midY - size.height / 2).rounded(.down),
            width: size.width, height: size.height)
    }

    /// The palette's origin: left of `frame`, its top level with the frame's top; right of it when
    /// there is no room on the left; at the display's left edge, over the frame, when there is room
    /// on neither side. Always inside `visibleFrame`.
    static func paletteOrigin(size: CGSize, beside frame: CGRect, in visibleFrame: CGRect) -> CGPoint {
        let left = frame.minX - paletteGap - size.width
        let right = frame.maxX + paletteGap
        let minX = visibleFrame.minX + screenMargin
        let x: CGFloat
        if left >= minX {
            x = left
        } else if right <= visibleFrame.maxX - screenMargin - size.width {
            x = right
        } else {
            x = minX
        }
        let y = min(
            max(frame.maxY - size.height, visibleFrame.minY + screenMargin),
            visibleFrame.maxY - screenMargin - size.height)
        return CGPoint(x: x.rounded(), y: y.rounded())
    }

    /// Between the palette and the Size list.
    static let popoverGap: CGFloat = 6

    /// The Size list's origin: right of `palette`, towards the frame it sits left of, or left of it
    /// when there is no room on the right, its top level with `anchorTop` (the Size button's top);
    /// always inside `visibleFrame`, vertically.
    static func popoverOrigin(
        size: CGSize, beside palette: CGRect, anchorTop: CGFloat, in visibleFrame: CGRect
    )
        -> CGPoint
    {
        var x = palette.maxX + popoverGap
        if x + size.width > visibleFrame.maxX - screenMargin { x = palette.minX - popoverGap - size.width }
        let y = min(
            max(anchorTop - size.height, visibleFrame.minY + screenMargin),
            visibleFrame.maxY - screenMargin - size.height)
        return CGPoint(x: x.rounded(), y: y.rounded())
    }

    /// Between the palette and a button's hover label.
    static let hoverLabelGap: CGFloat = 6

    /// The x of a hover label `width` wide: beside `palette` on its side away from `frame`, or
    /// towards the frame when that side has no room in `visibleFrame`; right of the palette without a
    /// frame.
    static func hoverLabelX(
        width: CGFloat, beside palette: CGRect, frame: CGRect?, in visibleFrame: CGRect
    ) -> CGFloat {
        let left = palette.minX - hoverLabelGap - width
        let right = palette.maxX + hoverLabelGap
        let fitsLeft = left >= visibleFrame.minX
        let fitsRight = right + width <= visibleFrame.maxX
        let x: CGFloat
        if let frame, frame.midX > palette.midX {
            x = fitsLeft || !fitsRight ? left : right
        } else {
            x = fitsRight || !fitsLeft ? right : left
        }
        return x.rounded()
    }
}
