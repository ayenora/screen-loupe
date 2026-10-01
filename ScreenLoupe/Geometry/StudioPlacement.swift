import CoreGraphics

/// Where the Screenshot studio's frame and palette go when nothing is kept for them. AppKit global coordinates, y up.
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
    /// Around the palette's buttons, inside its window: the same on all four sides.
    static let paletteMargin: CGFloat = 8

    /// The palette window's width for buttons `buttonWidth` wide: its title bar adds no width.
    static func paletteWidth(buttonWidth: CGFloat) -> CGFloat {
        buttonWidth + 2 * paletteMargin
    }

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

    /// A saved palette origin for a palette `size` big, moved as little as needed to keep the palette
    /// inside `visibleFrame`: a palette left at the top grows upward from its bottom-left corner when
    /// it gets taller, and its level is above the menu bar's. The user parked it there, so no margin is
    /// added. Larger than `visibleFrame`, its top-left corner stays inside, so the title bar stays in
    /// reach.
    static func restoredPaletteOrigin(_ saved: CGPoint, size: CGSize, in visibleFrame: CGRect) -> CGPoint {
        let x = max(min(saved.x, visibleFrame.maxX - size.width), visibleFrame.minX)
        let y = min(max(saved.y, visibleFrame.minY), visibleFrame.maxY - size.height)
        return CGPoint(x: x, y: y)
    }

    /// Between the palette and a menu it pops up.
    static let menuGap: CGFloat = 6

    /// Where a menu the palette pops up goes, `size` big, as the top-left corner
    /// `NSMenu.popUp(positioning:at:in:)` takes in screen coordinates: beside `palette` on its side
    /// away from the studio's `frame` (right of it without a frame), or on the other side when that
    /// one has no room in `visibleFrame` and the other has; its top level with `anchorTop`, the top
    /// of the button that opened it. Where neither side has room, or the menu would pass the
    /// display's top or bottom, the system moves it onto the screen. Whole points.
    static func menuTopLeft(
        size: CGSize, beside palette: CGRect, anchorTop: CGFloat, frame: CGRect?, in visibleFrame: CGRect
    ) -> CGPoint {
        let left = palette.minX - menuGap - size.width
        let right = palette.maxX + menuGap
        let fitsLeft = left >= visibleFrame.minX
        let fitsRight = right + size.width <= visibleFrame.maxX
        let x: CGFloat
        if let frame, frame.midX > palette.midX {
            x = fitsLeft || !fitsRight ? left : right
        } else {
            x = fitsRight || !fitsLeft ? right : left
        }
        return CGPoint(x: x.rounded(), y: anchorTop.rounded())
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

    /// Between One Window's notice or countdown and what it sits beside.
    static let oneWindowNoticeGap: CGFloat = 6

    /// Where One Window's notice or countdown goes while the frame is hidden, `size` big: right of
    /// `anchor` — the chosen window's name, or the palette level with its One Window button while no
    /// window is chosen — or left of it when `visibleFrame` has no room on the right; centred on
    /// its row and kept inside `visibleFrame`, on whole points.
    static func oneWindowNotice(size: CGSize, beside anchor: CGRect, in visibleFrame: CGRect) -> CGRect {
        var x = anchor.maxX + oneWindowNoticeGap
        if x + size.width > visibleFrame.maxX - screenMargin { x = anchor.minX - oneWindowNoticeGap - size.width }
        x = min(max(x, visibleFrame.minX + screenMargin), visibleFrame.maxX - screenMargin - size.width)
        let y = min(
            max(anchor.midY - size.height / 2, visibleFrame.minY + screenMargin),
            visibleFrame.maxY - screenMargin - size.height)
        return CGRect(origin: CGPoint(x: x.rounded(), y: y.rounded()), size: size)
    }
}
