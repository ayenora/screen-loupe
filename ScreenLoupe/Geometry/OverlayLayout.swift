import CoreGraphics

/// A resize handle of the Capture Area frame.
enum OverlayHandle: CaseIterable, Sendable {
    case topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight

    var movesMinX: Bool { self == .topLeft || self == .left || self == .bottomLeft }
    var movesMaxX: Bool { self == .topRight || self == .right || self == .bottomRight }
    /// Top is `maxY`: AppKit global coordinates are y up.
    var movesMaxY: Bool { self == .topLeft || self == .top || self == .topRight }
    var movesMinY: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }
}

/// What a mouse press on the frame does.
enum OverlayHitTarget: Equatable, Sendable {
    case move
    case resize(OverlayHandle)
}

enum TabPlacement: Equatable, Sendable {
    case above, below, inside
}

/// Sizes of the frame's parts, in points (docs/design.md §4).
struct OverlayMetrics: Sendable {
    /// The line is drawn this far outside the captured rect, so every captured pixel stays visible.
    var lineWidth: CGFloat = 1
    /// The translucent move band outside the line, shown on hover.
    var bandWidth: CGFloat = 5
    var handleSize: CGFloat = 8
    /// Handles are easier to grab than they look.
    var handleHitSize: CGFloat = 12
    var tabGap: CGFloat = 10
    var tabHeight: CGFloat = 22
    var tabInsideInset: CGFloat = 12
    var labelGap: CGFloat = 6
    var labelHeight: CGFloat = 16
    var screenMargin: CGFloat = 6
    /// How close to the line the cursor has to come for the handles and the tab to appear.
    var hoverReach: CGFloat = 14
    /// Room around the frame kept inside the overlay window for the band, handles and the tab.
    var windowPadding: CGFloat = 40

    static let standard = OverlayMetrics()
}

/// Where every part of the Capture Area frame goes, in AppKit global coordinates.
struct OverlayLayout: Equatable, Sendable {
    var captureRect: CGRect
    var tabRect: CGRect
    var tabPlacement: TabPlacement
    var labelRect: CGRect
    /// The overlay window's frame: the frame, its band and handles, the tab and the label.
    var windowFrame: CGRect

    init(
        captureRect: CGRect, screenFrame: CGRect, tabWidth: CGFloat, labelWidth: CGFloat,
        metrics m: OverlayMetrics = .standard
    ) {
        self.captureRect = captureRect
        let r = captureRect
        let screen = screenFrame

        // Tab: above → below → inside at the top. Centred, but kept off the screen edges.
        let tabY: CGFloat
        if r.maxY + m.tabGap + m.tabHeight <= screen.maxY - m.screenMargin {
            tabPlacement = .above
            tabY = r.maxY + m.tabGap
        } else if r.minY - m.tabGap - m.tabHeight >= screen.minY + m.screenMargin {
            tabPlacement = .below
            tabY = r.minY - m.tabGap - m.tabHeight
        } else {
            tabPlacement = .inside
            tabY = min(r.maxY, screen.maxY) - m.tabInsideInset - m.tabHeight
        }
        let tabX = Self.clamp(
            r.midX - tabWidth / 2, lower: screen.minX + m.screenMargin, upper: screen.maxX - m.screenMargin - tabWidth)
        tabRect = CGRect(x: tabX.rounded(), y: tabY.rounded(), width: tabWidth, height: m.tabHeight)

        // At-rest label: below on the right, or inside the bottom-right corner.
        let labelY: CGFloat
        if r.minY - m.labelGap - m.labelHeight >= screen.minY + m.screenMargin {
            labelY = r.minY - m.labelGap - m.labelHeight
        } else {
            labelY = max(r.minY, screen.minY) + m.labelGap
        }
        let labelX = Self.clamp(
            r.maxX - labelWidth, lower: screen.minX + m.screenMargin, upper: screen.maxX - m.screenMargin - labelWidth)
        labelRect = CGRect(x: labelX.rounded(), y: labelY.rounded(), width: labelWidth, height: m.labelHeight)

        windowFrame =
            r.insetBy(dx: -m.windowPadding, dy: -m.windowPadding)
            .union(tabRect.insetBy(dx: -8, dy: -8))
            .union(labelRect.insetBy(dx: -8, dy: -8))
            .integral
    }

    /// Where each handle is drawn: centred on the line.
    func handleRect(_ handle: OverlayHandle, size: CGFloat) -> CGRect {
        let r = captureRect
        let x: CGFloat = handle.movesMinX ? r.minX : handle.movesMaxX ? r.maxX : r.midX
        let y: CGFloat = handle.movesMinY ? r.minY : handle.movesMaxY ? r.maxY : r.midY
        return CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size)
    }

    /// What pressing at `point` does, or `nil` when the press belongs to the app underneath.
    func hitTarget(at point: CGPoint, metrics m: OverlayMetrics = .standard) -> OverlayHitTarget? {
        for handle in OverlayHandle.allCases where handleRect(handle, size: m.handleHitSize).contains(point) {
            return .resize(handle)
        }
        if tabRect.contains(point) { return .move }
        let outer = captureRect.insetBy(dx: -(m.lineWidth + m.bandWidth), dy: -(m.lineWidth + m.bandWidth))
        if outer.contains(point) && !captureRect.contains(point) { return .move }
        return nil
    }

    /// Whether the cursor is close enough to the frame to reveal the handles and the tab.
    func isInHoverZone(_ point: CGPoint, metrics m: OverlayMetrics = .standard) -> Bool {
        if tabRect.contains(point) || labelRect.contains(point) { return true }
        let outer = captureRect.insetBy(dx: -m.hoverReach, dy: -m.hoverReach)
        let inner = captureRect.insetBy(dx: m.hoverReach / 2, dy: m.hoverReach / 2)
        return outer.contains(point) && (inner.isNull || !inner.contains(point))
    }

    private static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        // A tab wider than the screen hugs the left margin.
        max(lower, min(value, upper))
    }
}

/// Moving and resizing the Capture Area. Global coordinates, y up; results are not snapped.
enum CaptureAreaEditing {
    static let minimumSize = CGSize(width: 8, height: 8)

    /// `rect` with the edges `handle` controls moved by `delta`. The opposite edges stay put and the
    /// size never drops below `minimumSize`.
    static func resized(_ rect: CGRect, handle: OverlayHandle, by delta: CGVector) -> CGRect {
        var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        if handle.movesMinX { minX = min(minX + delta.dx, maxX - minimumSize.width) }
        if handle.movesMaxX { maxX = max(maxX + delta.dx, minX + minimumSize.width) }
        if handle.movesMinY { minY = min(minY + delta.dy, maxY - minimumSize.height) }
        if handle.movesMaxY { maxY = max(maxY + delta.dy, minY + minimumSize.height) }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    enum ArrowKey: Sendable { case left, right, up, down }

    /// Arrow-key editing: moves by `step`, or with `resize` grows/shrinks keeping the top-left corner
    /// fixed — Right/Down grow, Left/Up shrink.
    static func nudged(_ rect: CGRect, key: ArrowKey, step: CGFloat, resize: Bool) -> CGRect {
        if !resize {
            switch key {
            case .left: return rect.offsetBy(dx: -step, dy: 0)
            case .right: return rect.offsetBy(dx: step, dy: 0)
            case .up: return rect.offsetBy(dx: 0, dy: step)
            case .down: return rect.offsetBy(dx: 0, dy: -step)
            }
        }
        switch key {
        case .right: return resized(rect, handle: .right, by: CGVector(dx: step, dy: 0))
        case .left: return resized(rect, handle: .right, by: CGVector(dx: -step, dy: 0))
        case .down: return resized(rect, handle: .bottom, by: CGVector(dx: 0, dy: -step))
        case .up: return resized(rect, handle: .bottom, by: CGVector(dx: 0, dy: step))
        }
    }
}
