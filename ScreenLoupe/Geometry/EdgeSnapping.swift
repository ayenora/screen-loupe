import CoreGraphics

/// Snapping the Capture Area to window and display edges while ⌘ is held, and picking a window
/// under the cursor (docs/product.md, Capture Area). Global coordinates, y up; results are not
/// snapped to pixels.
enum EdgeSnapping {
    /// How close an edge has to come to a target's edge to snap to it, in points.
    static let reach: CGFloat = 8

    /// `rect` with each edge `handle` moves snapped to the nearest target edge within `reach`. An
    /// edge snaps only to targets beside it: a left edge to a window that spans some of its height.
    /// A snap that would make the area smaller than `CaptureAreaEditing.minimumSize` is skipped.
    static func resized(_ rect: CGRect, handle: OverlayHandle, targets: [CGRect], reach: CGFloat = reach) -> CGRect {
        let minimum = CaptureAreaEditing.minimumSize
        let xs = verticalEdges(beside: rect, in: targets)
        let ys = horizontalEdges(beside: rect, in: targets)
        var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        if handle.movesMinX, let x = nearest(to: minX, in: xs, reach: reach), maxX - x >= minimum.width { minX = x }
        if handle.movesMaxX, let x = nearest(to: maxX, in: xs, reach: reach), x - minX >= minimum.width { maxX = x }
        if handle.movesMinY, let y = nearest(to: minY, in: ys, reach: reach), maxY - y >= minimum.height { minY = y }
        if handle.movesMaxY, let y = nearest(to: maxY, in: ys, reach: reach), y - minY >= minimum.height { maxY = y }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// `rect` moved so the edge closest to a target edge within `reach` lies on it, on each axis on
    /// its own. The size never changes.
    static func moved(_ rect: CGRect, targets: [CGRect], reach: CGFloat = reach) -> CGRect {
        let dx = offset(for: [rect.minX, rect.maxX], in: verticalEdges(beside: rect, in: targets), reach: reach)
        let dy = offset(for: [rect.minY, rect.maxY], in: horizontalEdges(beside: rect, in: targets), reach: reach)
        return rect.offsetBy(dx: dx, dy: dy)
    }

    /// The frontmost of `windows`, listed front to back, that contains `point`.
    static func window(at point: CGPoint, in windows: [CGRect]) -> CGRect? {
        windows.first { $0.contains(point) }
    }

    private static func verticalEdges(beside rect: CGRect, in targets: [CGRect]) -> [CGFloat] {
        targets.filter { $0.minY < rect.maxY && $0.maxY > rect.minY }.flatMap { [$0.minX, $0.maxX] }
    }

    private static func horizontalEdges(beside rect: CGRect, in targets: [CGRect]) -> [CGFloat] {
        targets.filter { $0.minX < rect.maxX && $0.maxX > rect.minX }.flatMap { [$0.minY, $0.maxY] }
    }

    private static func nearest(to value: CGFloat, in edges: [CGFloat], reach: CGFloat) -> CGFloat? {
        edges.filter { abs($0 - value) <= reach }.min { abs($0 - value) < abs($1 - value) }
    }

    private static func offset(for values: [CGFloat], in edges: [CGFloat], reach: CGFloat) -> CGFloat {
        let offsets = values.compactMap { value in nearest(to: value, in: edges, reach: reach).map { $0 - value } }
        return offsets.min { abs($0) < abs($1) } ?? 0
    }
}
