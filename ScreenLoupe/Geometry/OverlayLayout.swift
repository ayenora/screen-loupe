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
    /// The pin button beside the tab.
    case pin
    /// The button beside the pin that brings the Viewer forward.
    case raiseViewer
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
    /// The square pin button beside the tab, as tall as the tab.
    var pinGap: CGFloat = 4
    /// The position box beside the frame, outside the band and handles.
    var positionGap: CGFloat = 12
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
    var pinRect: CGRect
    /// The button that brings the Viewer forward, beside the pin, away from the tab.
    var raiseRect: CGRect
    /// The L T R B box: right of the frame, or left of it when there is no room on the right.
    var positionRect: CGRect
    /// The overlay window's frame: the frame, its band and handles, the tab, the label and the box.
    var windowFrame: CGRect

    init(
        captureRect: CGRect, screenFrame: CGRect, tabWidth: CGFloat, labelWidth: CGFloat,
        positionSize: CGSize = .zero, metrics m: OverlayMetrics = .standard
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
        // The pin and the raise buttons: right of the tab, or left of it at the screen's right edge,
        // the pin next to the tab either way.
        let button = m.tabHeight + m.pinGap
        var pinX = tabRect.maxX + m.pinGap
        var raiseX = pinX + button
        if raiseX + m.tabHeight > screen.maxX - m.screenMargin {
            pinX = tabRect.minX - button
            raiseX = pinX - button
        }
        pinRect = CGRect(x: pinX, y: tabRect.minY, width: m.tabHeight, height: m.tabHeight)
        raiseRect = CGRect(x: raiseX, y: tabRect.minY, width: m.tabHeight, height: m.tabHeight)

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

        // Position box: its top level with the frame's top, kept on screen.
        var boxX = r.maxX + m.positionGap
        if boxX + positionSize.width > screen.maxX - m.screenMargin {
            boxX = r.minX - m.positionGap - positionSize.width
        }
        boxX = Self.clamp(
            boxX, lower: screen.minX + m.screenMargin, upper: screen.maxX - m.screenMargin - positionSize.width)
        let boxY = Self.clamp(
            r.maxY - positionSize.height, lower: screen.minY + m.screenMargin,
            upper: screen.maxY - m.screenMargin - positionSize.height)
        positionRect = CGRect(
            x: boxX.rounded(), y: boxY.rounded(), width: positionSize.width, height: positionSize.height)

        windowFrame =
            r.insetBy(dx: -m.windowPadding, dy: -m.windowPadding)
            .union(tabRect.insetBy(dx: -8, dy: -8))
            .union(labelRect.insetBy(dx: -8, dy: -8))
            .union(positionRect.insetBy(dx: -8, dy: -8))
            .union(pinRect.insetBy(dx: -8, dy: -8))
            .union(raiseRect.insetBy(dx: -8, dy: -8))
            .integral
    }

    /// Where each handle is drawn: centred on the line.
    func handleRect(_ handle: OverlayHandle, size: CGFloat) -> CGRect {
        let r = captureRect
        let x: CGFloat = handle.movesMinX ? r.minX : handle.movesMaxX ? r.maxX : r.midX
        let y: CGFloat = handle.movesMinY ? r.minY : handle.movesMaxY ? r.maxY : r.midY
        return CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size)
    }

    /// What pressing at `point` does, or `nil` when the press belongs to the app underneath. A pinned
    /// frame only answers its pin and raise buttons.
    func hitTarget(at point: CGPoint, metrics m: OverlayMetrics = .standard, pinned: Bool = false) -> OverlayHitTarget?
    {
        if pinRect.contains(point) { return .pin }
        if raiseRect.contains(point) { return .raiseViewer }
        if pinned { return nil }
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
        if tabRect.contains(point) || labelRect.contains(point) || positionRect.contains(point)
            || pinRect.contains(point) || raiseRect.contains(point)
        {
            return true
        }
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
    static let minimumSize = CGSize(width: 64, height: 64)

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
