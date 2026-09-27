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
    /// The pin button beside the tab: turns the chosen lock on and off.
    case pin
    /// The ▾ attached to the pin: the menu of locks.
    case pinMenu
    /// The button beside the pin that brings the Viewer forward.
    case raiseViewer
    /// The button after it that picks a window for the area to take.
    case pickWindow
    /// The button after the pin's ▾ that turns the viewport handle on and off.
    case viewportButton
    /// The handle on the outline of the part the Viewer shows: dragging it pans the Viewer.
    case viewportHandle
}

/// What keeps the Capture Area in place while the pin is on (docs/product.md, Capture Area). Moving
/// is blocked by every lock; Fit to Window works with any, as a deliberate command.
enum CaptureAreaLock: String, Codable, CaseIterable, Sendable {
    /// Neither moves nor resizes.
    case pinned
    /// Doesn't move, but every handle still resizes it.
    case fixedPosition
    /// Moves only with the window it is attached to; every handle still resizes it.
    case magnet

    var allowsResize: Bool { self != .pinned }

    /// Arrow keys: a move never, a resize (with Option) only when the handles resize too.
    func allowsNudge(resizing: Bool) -> Bool { resizing && allowsResize }

    /// Whether the pin was on, as saved: under `captureAreaLocked`, else under `captureAreaPinned`,
    /// where the plain pin was saved before there was a choice of locks. `isOn` is `nil` when
    /// neither can be read.
    struct SavedPin: Decodable {
        let isOn: Bool?

        private enum CodingKeys: String, CodingKey {
            case captureAreaLocked, captureAreaPinned
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            isOn =
                (try? c.decodeIfPresent(Bool.self, forKey: .captureAreaLocked))
                ?? (try? c.decodeIfPresent(Bool.self, forKey: .captureAreaPinned))
        }
    }
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
    /// The ▾ attached to the pin's right, which opens the menu of locks.
    var pinMenuWidth: CGFloat = 13
    /// The pill on the outline of the part the Viewer shows, while the viewport handle is on.
    var viewportHandleSize = CGSize(width: 30, height: 18)
    /// The position box beside the frame, outside the band and handles.
    var positionGap: CGFloat = 12
    var screenMargin: CGFloat = 6
    /// How close to the line the cursor has to come for the handles and the tab to appear.
    var hoverReach: CGFloat = 14
    /// Room around the frame kept inside the overlay window for the band, handles and the tab.
    var windowPadding: CGFloat = 40

    static let standard = OverlayMetrics()
}

/// Where every part of the Capture Area frame goes, in AppKit global coordinates. The Screenshot
/// studio's frame is laid out the same way without the lock buttons: its pin, ▾ and raise button are
/// `.null`, so nothing hit-tests or hovers there, and the pick button sits beside the tab.
struct OverlayLayout: Equatable, Sendable {
    var captureRect: CGRect
    var tabRect: CGRect
    var tabPlacement: TabPlacement
    var labelRect: CGRect
    var pinRect: CGRect
    /// The pin's ▾, attached on its right.
    var pinMenuRect: CGRect
    /// The button that turns the viewport handle on and off, beside the pin, away from the tab.
    var viewportRect: CGRect
    /// The button that brings the Viewer forward, after the viewport button.
    var raiseRect: CGRect
    /// The button that picks a window for the area, after the raise button.
    var pickRect: CGRect
    /// The L T R B box: right of the frame, or left of it when there is no room on the right; never
    /// over the rect it avoids (the studio's palette) while there is room elsewhere beside it.
    var positionRect: CGRect
    /// A short notice beside the tab, away from the buttons; empty when there is none.
    var noticeRect: CGRect
    /// The overlay window's frame: the frame, its band and handles, the tab, the label, the box and
    /// the notice.
    var windowFrame: CGRect

    init(
        captureRect: CGRect, screenFrame: CGRect, tabWidth: CGFloat, labelWidth: CGFloat,
        positionSize: CGSize = .zero, positionAvoiding: CGRect = .null, noticeWidth: CGFloat = 0,
        lockButtons: Bool = true, metrics m: OverlayMetrics = .standard
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
        // The pin with its ▾, the viewport, raise and pick buttons: right of the tab, or left of it at
        // the screen's right edge, the pin next to the tab either way. Without the lock buttons, the
        // pick button alone.
        let button = m.tabHeight + m.pinGap
        let split = lockButtons ? m.tabHeight + m.pinMenuWidth + m.pinGap : 0
        let single = lockButtons ? button : 0
        var pinX = tabRect.maxX + m.pinGap
        var viewportX = pinX + split
        var raiseX = viewportX + single
        var pickX = raiseX + single
        if pickX + m.tabHeight > screen.maxX - m.screenMargin {
            pinX = tabRect.minX - split
            viewportX = pinX - single
            raiseX = viewportX - single
            pickX = raiseX - button
        }
        let buttonsOnRight = pickX > tabRect.maxX
        if lockButtons {
            pinRect = CGRect(x: pinX, y: tabRect.minY, width: m.tabHeight, height: m.tabHeight)
            pinMenuRect = CGRect(x: pinRect.maxX, y: tabRect.minY, width: m.pinMenuWidth, height: m.tabHeight)
            viewportRect = CGRect(x: viewportX, y: tabRect.minY, width: m.tabHeight, height: m.tabHeight)
            raiseRect = CGRect(x: raiseX, y: tabRect.minY, width: m.tabHeight, height: m.tabHeight)
        } else {
            pinRect = .null
            pinMenuRect = .null
            viewportRect = .null
            raiseRect = .null
        }
        pickRect = CGRect(x: pickX, y: tabRect.minY, width: m.tabHeight, height: m.tabHeight)

        // Notice: left of the tab, or past the pick button when the tab is at the screen's left edge.
        // With the buttons left of the tab, past the pick button on that side.
        var noticeX = (buttonsOnRight ? tabRect.minX : pickRect.minX) - m.pinGap - noticeWidth
        if buttonsOnRight, noticeX < screen.minX + m.screenMargin {
            noticeX = pickRect.maxX + m.pinGap
        }
        noticeRect =
            noticeWidth > 0
            ? CGRect(
                x: noticeX.rounded(), y: (tabRect.midY - m.labelHeight / 2).rounded(), width: noticeWidth,
                height: m.labelHeight)
            : .zero

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

        // Position box: its top level with the frame's top, kept on screen: right of the frame, or
        // left of it when the right has no room. Where that covers `positionAvoiding`, the first of
        // the frame's other side and beyond the avoided rect, away from the frame, that has room and
        // covers nothing.
        let boxY = Self.clamp(
            r.maxY - positionSize.height, lower: screen.minY + m.screenMargin,
            upper: screen.maxY - m.screenMargin - positionSize.height)
        let fits = { (x: CGFloat) in
            x >= screen.minX + m.screenMargin && x + positionSize.width <= screen.maxX - m.screenMargin
        }
        let isClear = { (x: CGFloat) in
            !CGRect(x: x, y: boxY, width: positionSize.width, height: positionSize.height)
                .intersects(positionAvoiding)
        }
        let rightX = r.maxX + m.positionGap
        let leftX = r.minX - m.positionGap - positionSize.width
        var boxX = rightX + positionSize.width <= screen.maxX - m.screenMargin ? rightX : leftX
        if !isClear(boxX) {
            // Beyond the avoided rect: on its side away from the frame.
            let avoided = positionAvoiding
            let beyond =
                avoided.midX < r.midX
                ? avoided.minX - m.positionGap - positionSize.width : avoided.maxX + m.positionGap
            boxX = [rightX, leftX, beyond].first { fits($0) && isClear($0) } ?? boxX
        }
        boxX = Self.clamp(
            boxX, lower: screen.minX + m.screenMargin, upper: screen.maxX - m.screenMargin - positionSize.width)
        positionRect = CGRect(
            x: boxX.rounded(), y: boxY.rounded(), width: positionSize.width, height: positionSize.height)

        var frame =
            r.insetBy(dx: -m.windowPadding, dy: -m.windowPadding)
            .union(tabRect.insetBy(dx: -8, dy: -8))
            .union(labelRect.insetBy(dx: -8, dy: -8))
            .union(positionRect.insetBy(dx: -8, dy: -8))
            .union(pinRect.insetBy(dx: -8, dy: -8))
            .union(pinMenuRect.insetBy(dx: -8, dy: -8))
            .union(viewportRect.insetBy(dx: -8, dy: -8))
            .union(raiseRect.insetBy(dx: -8, dy: -8))
            .union(pickRect.insetBy(dx: -8, dy: -8))
        if noticeWidth > 0 {
            frame = frame.union(noticeRect.insetBy(dx: -8, dy: -8))
        }
        windowFrame = frame.integral
    }

    /// Where each handle is drawn: centred on the line.
    func handleRect(_ handle: OverlayHandle, size: CGFloat) -> CGRect {
        let r = captureRect
        let x: CGFloat = handle.movesMinX ? r.minX : handle.movesMaxX ? r.maxX : r.midX
        let y: CGFloat = handle.movesMinY ? r.minY : handle.movesMaxY ? r.maxY : r.midY
        return CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size)
    }

    /// What pressing at `point` does, or `nil` when the press belongs to the app underneath. A locked
    /// frame answers its buttons and, when `lock` allows resizing, its handles, but never moves:
    /// picking a window is a command, not a drag. `viewportHandle` is the viewport handle's rect, `nil`
    /// while it isn't shown: it moves the Viewer, not the area, so it takes a press on any lock, over
    /// the handles and the tab; only the buttons keep theirs.
    func hitTarget(
        at point: CGPoint, metrics m: OverlayMetrics = .standard, lock: CaptureAreaLock? = nil,
        viewportHandle: CGRect? = nil
    ) -> OverlayHitTarget? {
        if pinRect.contains(point) { return .pin }
        if pinMenuRect.contains(point) { return .pinMenu }
        if viewportRect.contains(point) { return .viewportButton }
        if raiseRect.contains(point) { return .raiseViewer }
        if pickRect.contains(point) { return .pickWindow }
        if viewportHandle?.contains(point) == true { return .viewportHandle }
        if let lock, !lock.allowsResize { return nil }
        for handle in OverlayHandle.allCases where handleRect(handle, size: m.handleHitSize).contains(point) {
            return .resize(handle)
        }
        if lock != nil { return nil }
        if tabRect.contains(point) { return .move }
        let outer = captureRect.insetBy(dx: -(m.lineWidth + m.bandWidth), dy: -(m.lineWidth + m.bandWidth))
        if outer.contains(point) && !captureRect.contains(point) { return .move }
        return nil
    }

    /// The viewport handle for `viewedPart`, the part of the area the Viewer shows: centred on its top
    /// edge, or just inside the captured rect's top where it would stick out above it, and kept
    /// within the rect's sides.
    func viewportHandleRect(for viewedPart: CGRect, metrics m: OverlayMetrics = .standard) -> CGRect {
        let size = m.viewportHandleSize
        let x = Self.clamp(
            viewedPart.midX - size.width / 2, lower: captureRect.minX, upper: captureRect.maxX - size.width)
        let y = min(viewedPart.maxY - size.height / 2, captureRect.maxY - size.height)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// Whether the cursor is close enough to the frame to reveal the handles and the tab.
    func isInHoverZone(_ point: CGPoint, metrics m: OverlayMetrics = .standard) -> Bool {
        if tabRect.contains(point) || labelRect.contains(point) || positionRect.contains(point)
            || pinRect.contains(point) || pinMenuRect.contains(point) || viewportRect.contains(point)
            || raiseRect.contains(point) || pickRect.contains(point)
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

    /// `rect` made square for a Shift-drag of a corner `handle`: the longer side decides, and the
    /// corner opposite the handle stays put. An edge handle leaves `rect` as it is.
    static func squared(_ rect: CGRect, handle: OverlayHandle) -> CGRect {
        let movesX = handle.movesMinX || handle.movesMaxX
        let movesY = handle.movesMinY || handle.movesMaxY
        guard movesX && movesY else { return rect }
        let side = max(rect.width, rect.height)
        let x = handle.movesMinX ? rect.maxX - side : rect.minX
        let y = handle.movesMinY ? rect.maxY - side : rect.minY
        return CGRect(x: x, y: y, width: side, height: side)
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
