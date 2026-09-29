import CoreGraphics
import Foundation

/// A window of another app as the window list reports it.
struct ScreenWindow: Equatable, Sendable {
    var id: CGWindowID
    /// In AppKit global coordinates.
    var frame: CGRect
    /// 0 for an ordinary window.
    var layer: Int
    var isOnScreen: Bool
    var alpha: Double

    /// An ordinary window that shows: on the normal layer, not transparent, not empty. What the window
    /// picker, ⌘-snapping and the magnet take.
    var isOrdinaryAndVisible: Bool { layer == 0 && alpha > 0 && !frame.isEmpty }
}

/// Picking a window, and the magnet that keeps the Capture Area on one. Global coordinates, y up; results are not
/// snapped to pixels.
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

    // MARK: Fitted

    /// How far, in points, each edge of the area may lie from the window's for the area to be fitted
    /// to it. Fit to Window snaps each edge of the window's bounds to the display's pixels, which moves
    /// it by at most half a pixel: half a point on a 1× display, a quarter on a 2× one.
    static let fitTolerance: CGFloat = 1

    /// Whether `area` is fitted to `window`: each of its edges within `tolerance` points of the
    /// window's, inclusive.
    static func isFitted(_ area: CGRect, to window: CGRect, tolerance: CGFloat = fitTolerance) -> Bool {
        abs(area.minX - window.minX) <= tolerance && abs(area.maxX - window.maxX) <= tolerance
            && abs(area.minY - window.minY) <= tolerance && abs(area.maxY - window.maxY) <= tolerance
    }

    /// The area on `window`'s bounds: the window's rect, grown to `minimumSize` where the window is
    /// smaller, keeping the window's top-left corner as the magnet does.
    static func bounds(of window: CGRect, minimumSize: CGSize = CaptureAreaEditing.minimumSize) -> CGRect {
        let width = max(window.width, minimumSize.width)
        let height = max(window.height, minimumSize.height)
        return CGRect(x: window.minX, y: window.maxY - height, width: width, height: height)
    }

    /// One step of the magnet as its window changed from `previous` to `window`.
    enum Follow: Equatable, Sendable {
        /// The area was fitted to the window: it takes the window's new bounds (`bounds(of:)`), moved
        /// and resized. Snapped edge by edge, as Fit to Window is.
        case fitted(CGRect)
        /// It keeps its size and its offset from the window's top-left corner (`area(at:on:)`).
        case moved(CGRect)
    }

    /// Where the area goes when its window changes from `previous` to `window`: onto the new bounds
    /// if it was fitted to the old ones, else to `placement` on the new window. Stateless: whether the
    /// area is fitted is read from where it is, so a window that shrinks below `minimumSize` leaves
    /// the area at the minimum, no longer fitted, and following it from then on by its top-left.
    static func follow(
        area: CGRect, placement: CGRect, from previous: CGRect, to window: CGRect,
        minimumSize: CGSize = CaptureAreaEditing.minimumSize, tolerance: CGFloat = fitTolerance
    ) -> Follow {
        isFitted(area, to: previous, tolerance: tolerance)
            ? .fitted(bounds(of: window, minimumSize: minimumSize)) : .moved(self.area(at: placement, on: window))
    }

    /// The tab dragged `area` near its magnet's `window`: the window's rect when the area is the
    /// window's size, within `tolerance` points each way, and each of its edges within `reach` points
    /// of the window's, inclusive (the ⌘-snap's reach, `EdgeSnapping.reach`), so it lands fitted;
    /// `nil` otherwise, and for a window smaller than `minimumSize`, which the area can't fit.
    static func snappedOnto(
        _ window: CGRect, area: CGRect, reach: CGFloat = EdgeSnapping.reach, tolerance: CGFloat = fitTolerance,
        minimumSize: CGSize = CaptureAreaEditing.minimumSize
    ) -> CGRect? {
        guard window.width >= minimumSize.width, window.height >= minimumSize.height,
            abs(area.width - window.width) <= tolerance, abs(area.height - window.height) <= tolerance,
            isFitted(area, to: window, tolerance: reach)
        else { return nil }
        return window
    }

    // MARK: Holding the window

    /// Whether one read of the list still shows the magnet's window as held: an ordinary visible
    /// window on screen. The read is `nil` once the window is closed; a window minimised, hidden
    /// with its app or on another Space comes back empty too, or marked off screen.
    static func holds(_ window: ScreenWindow?) -> Bool {
        guard let window else { return false }
        return window.isOnScreen && window.isOrdinaryAndVisible
    }

    /// Between two reads of the window list, while the magnet holds a window or One Window watches one.
    static let readInterval: TimeInterval = 1.0 / 60

    /// Consecutive reads that don't hold the window before the magnet lets go, about 33 ms at 60 Hz:
    /// one odd read doesn't drop it.
    static let readsToLetGo = 2

    /// Whether `badReads` in a row let go of the window.
    static func letsGo(afterBadReads badReads: Int) -> Bool { badReads >= readsToLetGo }
}
