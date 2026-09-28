import CoreGraphics

/// Where the Viewer's side column is resized (docs/design.md, References): only a strip along its
/// left edge. A mouse-down anywhere else belongs to the panel under it, even where that panel takes
/// no click and AppKit passes it up to the column.
enum SidePanelEdge {
    /// How far into the column the left edge can be grabbed, in points.
    static let grab: CGFloat = 5

    /// The strip along the left edge of a column with `bounds`, in the column's coordinates.
    static func grabRect(in bounds: CGRect) -> CGRect {
        CGRect(x: bounds.minX, y: bounds.minY, width: min(grab, max(0, bounds.width)), height: bounds.height)
    }

    /// Whether a mouse-down at `point`, in the column's coordinates, starts a resize.
    static func grabs(_ point: CGPoint, in bounds: CGRect) -> Bool {
        grabRect(in: bounds).contains(point)
    }
}
