import CoreGraphics

/// A window of another app as the window list reports it.
struct ScreenWindow: Equatable, Sendable {
    var id: CGWindowID
    /// In AppKit global coordinates.
    var frame: CGRect
    /// 0 for an ordinary window.
    var layer: Int
    var isOnScreen: Bool
    var alpha: Double
}

/// Picking a window, and the magnet that keeps the Capture Area on one (docs/product.md, Capture
/// Area). Global coordinates, y up; results are not snapped to pixels.
enum WindowMagnet {
    /// The frontmost of `windows`, listed front to back, that contains `point`.
    static func window(at point: CGPoint, in windows: [ScreenWindow]) -> ScreenWindow? {
        windows.first { $0.frame.contains(point) }
    }

    /// The window a click on the magnet attaches to: the frontmost that contains the area's centre.
    static func window(under area: CGRect, in windows: [ScreenWindow]) -> ScreenWindow? {
        window(at: CGPoint(x: area.midX, y: area.midY), in: windows)
    }

    /// Where `area` sits on `window`: its top-left corner's offset from the window's, and its size.
    /// Taken when the magnet attaches and after the area is resized.
    static func placement(of area: CGRect, on window: CGRect) -> CGRect {
        CGRect(x: area.minX - window.minX, y: area.maxY - window.maxY, width: area.width, height: area.height)
    }

    /// The area at `placement` on `window`, as it moved: a window resized by its right or bottom edge
    /// leaves the area in place, one resized by its left or top edge carries it along, and its size
    /// never changes. Placed from the stored placement rather than shifted from the last area, so
    /// snapping to the pixels of each display it crosses adds up to no drift.
    static func area(at placement: CGRect, on window: CGRect) -> CGRect {
        CGRect(
            x: window.minX + placement.minX, y: window.maxY + placement.minY - placement.height,
            width: placement.width, height: placement.height)
    }

    /// Whether one read of the list still shows the magnet's window as held: an ordinary visible
    /// window on screen. The read is `nil` once the window is closed; a window minimised, hidden
    /// with its app or on another Space comes back empty too, or marked off screen.
    static func holds(_ window: ScreenWindow?) -> Bool {
        guard let window else { return false }
        return window.isOnScreen && window.layer == 0 && window.alpha > 0 && !window.frame.isEmpty
    }

    /// Consecutive reads that don't hold the window before the magnet lets go, about 33 ms at 60 Hz:
    /// one odd read doesn't drop it.
    static let readsToLetGo = 2

    /// Whether `badReads` in a row let go of the window.
    static func letsGo(afterBadReads badReads: Int) -> Bool { badReads >= readsToLetGo }
}
