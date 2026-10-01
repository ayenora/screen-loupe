import CoreGraphics

/// Where the floating zoom panel sits, kept relative to the Viewer: from the Viewer edge it is
/// nearer to, left or right, and from the Viewer's top. So a Viewer resized from its other edge
/// leaves the panel where it was beside it, and one moved takes it along.
struct ZoomPanelOffset: Codable, Equatable, Sendable {
    enum Edge: String, Codable, Sendable {
        case left, right
    }

    /// The Viewer edge the panel is kept from.
    var edge: Edge
    /// The panel's left side from that edge.
    var dx: CGFloat
    /// The panel's top from the Viewer's top; negative below it.
    var dy: CGFloat
}

/// The floating zoom panel's place beside the Viewer. AppKit global coordinates, y up.
enum ZoomPanelPlacement {
    /// Between the Viewer and the panel by default: the toolbar's gap between groups.
    static let gap: CGFloat = 8

    /// Beside the Viewer's right edge, top level with the Viewer's, `gap` away; beside its left edge
    /// when the right side has no room and the left has; on the right otherwise, which `origin` then
    /// keeps on screen. A side has room when the panel there lies across, left to right, inside the
    /// visible frame it would overlap most — of any display, so a Viewer at a display's edge can have
    /// its panel on the next display.
    static func defaultOffset(size: CGSize, viewer: CGRect, visibleFrames: [CGRect]) -> ZoomPanelOffset {
        let right = ZoomPanelOffset(edge: .right, dx: gap, dy: 0)
        let left = ZoomPanelOffset(edge: .left, dx: -gap - size.width, dy: 0)
        func fits(_ offset: ZoomPanelOffset) -> Bool {
            let rect = frame(size: size, offset: offset, viewer: viewer)
            guard let display = screen(for: rect, in: visibleFrames) else { return false }
            return rect.minX >= display.minX && rect.maxX <= display.maxX
        }
        return !fits(right) && fits(left) ? left : right
    }

    /// The offset of a panel at `panel` from the Viewer at `viewer`: from the Viewer edge nearer to
    /// the panel's middle; the right edge when the middles are level.
    static func offset(of panel: CGRect, from viewer: CGRect) -> ZoomPanelOffset {
        let edge: ZoomPanelOffset.Edge = panel.midX >= viewer.midX ? .right : .left
        let edgeX = edge == .right ? viewer.maxX : viewer.minX
        return ZoomPanelOffset(edge: edge, dx: panel.minX - edgeX, dy: panel.maxY - viewer.maxY)
    }

    /// The panel's frame at `offset` from the Viewer at `viewer`.
    static func frame(size: CGSize, offset: ZoomPanelOffset, viewer: CGRect) -> CGRect {
        let edgeX = offset.edge == .right ? viewer.maxX : viewer.minX
        return CGRect(
            x: edgeX + offset.dx, y: viewer.maxY + offset.dy - size.height, width: size.width, height: size.height)
    }

    /// The panel's origin at `offset` from the Viewer, kept on screen (`keptOnScreen`).
    static func origin(
        size: CGSize, offset: ZoomPanelOffset, viewer: CGRect, visibleFrames: [CGRect], fallback: CGRect
    ) -> CGPoint {
        keptOnScreen(
            frame(size: size, offset: offset, viewer: viewer), visibleFrames: visibleFrames, fallback: fallback)
    }

    /// `rect`'s origin moved just enough to lie inside the visible frame it overlaps most, or inside
    /// `fallback` (the Viewer's screen) when it overlaps none; its left and top edges stay inside when
    /// it is bigger than the frame. Whole points.
    static func keptOnScreen(_ rect: CGRect, visibleFrames: [CGRect], fallback: CGRect) -> CGPoint {
        let display = screen(for: rect, in: visibleFrames) ?? fallback
        let x = max(min(rect.minX, display.maxX - rect.width), display.minX)
        let top = min(max(rect.maxY, display.minY + rect.height), display.maxY)
        return CGPoint(x: x.rounded(), y: (top - rect.height).rounded())
    }

    /// The visible frame `rect` overlaps most, or `nil` when it overlaps none.
    private static func screen(for rect: CGRect, in visibleFrames: [CGRect]) -> CGRect? {
        func overlap(_ frame: CGRect) -> CGFloat {
            let common = frame.intersection(rect)
            return common.isNull ? 0 : common.width * common.height
        }
        return visibleFrames.max { overlap($0) < overlap($1) }.flatMap { overlap($0) > 0 ? $0 : nil }
    }
}
