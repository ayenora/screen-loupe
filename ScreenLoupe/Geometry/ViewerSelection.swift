import CoreGraphics

/// A handle of the Select tool's selection. Source pixels are y down, so the top edge is `minY`.
enum SelectionHandle: CaseIterable, Sendable {
    case topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight

    var movesMinX: Bool { self == .topLeft || self == .left || self == .bottomLeft }
    var movesMaxX: Bool { self == .topRight || self == .right || self == .bottomRight }
    var movesMinY: Bool { self == .topLeft || self == .top || self == .topRight }
    var movesMaxY: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }
}

/// The Select tool's selection (docs/product.md, Screenshots): a rectangle of whole source pixels,
/// from the Capture Area's top-left corner, so it stays on its pixels while the Viewer pans and zooms.
enum PixelSelection {
    /// The whole pixels a drag from `start` to `end` (viewport points in drawable pixels) covers,
    /// both ends included, inside the image. `nil` when the drag covers none of it.
    static func rect(from start: CGPoint, to end: CGPoint, in state: ZoomPanState) -> CGRect? {
        let a = state.sourcePoint(forViewportPoint: start)
        let b = state.sourcePoint(forViewportPoint: end)
        let minX = min(a.x, b.x).rounded(.down)
        let minY = min(a.y, b.y).rounded(.down)
        let maxX = max(a.x, b.x).rounded(.down) + 1
        let maxY = max(a.y, b.y).rounded(.down) + 1
        return clamped(CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY), to: state.contentSize)
    }

    /// `rect` with the edges `handle` controls moved to the pixel boundary nearest `point` (a
    /// source point). The opposite edges stay, and the selection keeps at least one pixel.
    static func resized(_ rect: CGRect, handle: SelectionHandle, to point: CGPoint, contentSize: CGSize) -> CGRect {
        var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        let x = min(max(point.x.rounded(), 0), contentSize.width)
        let y = min(max(point.y.rounded(), 0), contentSize.height)
        if handle.movesMinX { minX = min(x, maxX - 1) }
        if handle.movesMaxX { maxX = max(x, minX + 1) }
        if handle.movesMinY { minY = min(y, maxY - 1) }
        if handle.movesMaxY { maxY = max(y, minY + 1) }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// `rect` moved by `delta` source pixels, in whole pixels, kept inside the image.
    static func moved(_ rect: CGRect, by delta: CGPoint, contentSize: CGSize) -> CGRect {
        let x = min(max((rect.minX + delta.x).rounded(), 0), max(0, contentSize.width - rect.width))
        let y = min(max((rect.minY + delta.y).rounded(), 0), max(0, contentSize.height - rect.height))
        return CGRect(x: x, y: y, width: rect.width, height: rect.height)
    }

    /// `rect` after the Capture Area's top-left corner moved by `shift` source pixels, on the same
    /// screen pixels: counted from the new corner. It may reach past the new area; `clamped` shows
    /// the part inside, and the rest comes back if the area grows back over it.
    static func followingAreaOrigin(_ rect: CGRect, shift: CGPoint) -> CGRect {
        rect.offsetBy(dx: -shift.x, dy: -shift.y)
    }

    /// The part of `rect` inside an image of `contentSize`, or `nil` when none is (the Capture Area
    /// shrank under the selection).
    static func clamped(_ rect: CGRect, to contentSize: CGSize) -> CGRect? {
        let inside = rect.intersection(CGRect(origin: .zero, size: contentSize))
        guard !inside.isNull, inside.width >= 1, inside.height >= 1 else { return nil }
        return inside
    }

    /// Where a handle of `rect` sits in the viewport (drawable pixels): on the selection's edge.
    static func handlePoint(_ handle: SelectionHandle, of rect: CGRect, in state: ZoomPanState) -> CGPoint {
        let placed = state.imageRect(origin: rect.origin, size: rect.size)
        let x = handle.movesMinX ? placed.minX : handle.movesMaxX ? placed.maxX : placed.midX
        let y = handle.movesMinY ? placed.minY : handle.movesMaxY ? placed.maxY : placed.midY
        return CGPoint(x: x, y: y)
    }

    /// `12 × 5 px · x 11, y 11`: the size in pixels and the top-left corner from the Capture Area's.
    static func label(_ rect: CGRect) -> String {
        "\(Int(rect.width)) × \(Int(rect.height)) px · x \(Int(rect.minX)), y \(Int(rect.minY))"
    }
}

/// The region an Option-drag copies (docs/product.md, Screenshots): free, in whole drawable pixels
/// of the viewport, not snapped to source pixels.
enum ViewRegion {
    /// The rectangle between two viewport points, rounded to whole pixels and kept inside the
    /// viewport. `nil` when it is less than a pixel wide or high.
    static func rect(from start: CGPoint, to end: CGPoint, viewport: CGSize) -> CGRect? {
        let minX = max(0, min(start.x, end.x).rounded())
        let minY = max(0, min(start.y, end.y).rounded())
        let maxX = min(viewport.width, max(start.x, end.x).rounded())
        let maxY = min(viewport.height, max(start.y, end.y).rounded())
        guard maxX - minX >= 1, maxY - minY >= 1 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
