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
enum OverlayHitTarget: Hashable, Sendable {
    case move
    case resize(OverlayHandle)
    /// The pin button beside the tab: turns the chosen lock on and off.
    case pin
    /// The ▾ attached to the pin: the menu of locks.
    case pinMenu
    /// The button after the viewport button that brings the Viewer forward.
    case raiseViewer
    /// The button after it that picks a window for the area to take.
    case pickWindow
    /// The button after the pin's ▾, or after the margins button while it shows, that turns the
    /// viewport handle on and off.
    case viewportButton
    /// The "»" after the pin's ▾ that shows the buttons collapsed behind it.
    case moreButtons
    /// The handle on the outline of the part the Viewer shows: dragging it pans the Viewer.
    case viewportHandle
    /// The button right after the pin's ▾ that turns the margins on and off, while the area is fitted
    /// to its magnet's window.
    case marginsButton

    /// Whether a press with this click count does anything. A button after the pin's ▾ takes only a
    /// single click: expanding or collapsing the row puts another button where "»" was, which the
    /// second click of a double click would otherwise press.
    func takesPress(clickCount: Int) -> Bool {
        switch self {
        case .viewportButton, .moreButtons, .raiseViewer, .pickWindow, .marginsButton: clickCount <= 1
        default: true
        }
    }
}

/// What keeps the Capture Area in place while the pin is on (docs/product.md, Capture Area). Moving
/// by the line and the arrow keys is blocked by every lock, by the tab by all but the magnet; Fit to
/// Window works with any, as a deliberate command.
enum CaptureAreaLock: String, Codable, CaseIterable, Sendable {
    /// Neither moves nor resizes.
    case pinned
    /// Doesn't move, but every handle still resizes it.
    case fixedPosition
    /// Moves with the window it is attached to, and by its tab, which sets a new place on the window;
    /// every handle still resizes it, unless it is fitted to the window.
    case magnet

    var allowsResize: Bool { self != .pinned }

    /// Whether dragging the tab moves the area.
    var movesByTab: Bool { self == .magnet }

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
    /// The contrasting halo just outside the line, so it reads on any background.
    var haloWidth: CGFloat = 1
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
    /// Between the viewport handle and the outline it sits beside.
    var viewportHandleGap: CGFloat = 2
    /// Between the row of tab buttons and the name of the one under the pointer.
    var buttonNameGap: CGFloat = 4
    /// The position box beside the frame, outside the band and handles.
    var positionGap: CGFloat = 12
    /// Between the position box and the margins panel below it.
    var marginsPanelGap: CGFloat = 4
    var screenMargin: CGFloat = 6
    /// How close to the line the cursor has to come for the handles and the tab to appear.
    var hoverReach: CGFloat = 14
    /// Room around the frame kept inside the overlay window for the band, handles and the tab.
    var windowPadding: CGFloat = 40
    /// Room kept around each part beside the frame inside the overlay window, so nothing drawn at a
    /// part's edge, such as the tab's shadow, is cut off.
    var partPadding: CGFloat = 8

    static let standard = OverlayMetrics()
}

/// Where every part of the Capture Area frame goes, in AppKit global coordinates. A button that isn't
/// shown is `.null`, so nothing hit-tests or hovers there and the window doesn't make room for it. The
/// Screenshot studio's frame is laid out the same way without the lock buttons: its pin, ▾, margins,
/// viewport, raise and "»" buttons are `.null`, and the pick button sits beside the tab.
struct OverlayLayout: Equatable, Sendable {
    var captureRect: CGRect
    var tabRect: CGRect
    var tabPlacement: TabPlacement
    var labelRect: CGRect
    var pinRect: CGRect
    /// The pin's ▾, attached on its right.
    var pinMenuRect: CGRect
    /// The buttons after the pin's ▾, in order away from the tab: the viewport, raise and pick
    /// buttons, or collapsed, "»" in place of those it collapses.
    var rowButtons: [OverlayHitTarget]
    /// The buttons sit right of the tab; left of it at the screen's right edge.
    var buttonsOnRight: Bool
    /// The button that turns the viewport handle on and off, beside the pin, away from the tab.
    var viewportRect: CGRect
    /// The button that brings the Viewer forward, after the viewport button.
    var raiseRect: CGRect
    /// The button that picks a window for the area, after the raise button.
    var pickRect: CGRect
    /// The "»" that stands in for the collapsed buttons, after the pin's ▾ or the viewport button.
    var moreRect: CGRect
    /// The margins button, right after the pin's ▾, while the margins can be turned on.
    var marginsButtonRect: CGRect
    /// The L T R B box: right of the frame, or left of it when there is no room on the right; never
    /// over the rect it avoids (the studio's palette) while there is room elsewhere beside it.
    var positionRect: CGRect
    /// The margins panel below the position box, on the box's edge next to the frame; `.null` while
    /// the margins are off.
    var marginsPanelRect: CGRect
    /// The rect that is captured: `captureRect` less the margins, or `captureRect` itself.
    var innerRect: CGRect
    /// A short notice beside the tab, away from the buttons; empty when there is none.
    var noticeRect: CGRect
    /// The overlay window's frame: the frame, its band and handles, the tab, the label, the box, the
    /// margins panel and the notice.
    var windowFrame: CGRect

    /// `captureRect` is the frame's rect. `marginsButton`: the margins can be turned on, and their
    /// button shows. `innerRect`: what is captured, inside the frame; `nil` for the frame's rect.
    /// `marginsPanelSize`: the margins panel as it is now, `.zero` while the margins are off;
    /// `marginsPanelWidestWidth`: its expanded width, which picks the box's side, so expanding never
    /// moves it.
    init(
        captureRect: CGRect, screenFrame: CGRect, tabWidth: CGFloat, labelWidth: CGFloat,
        positionSize: CGSize = .zero, positionAvoiding: CGRect = .null, noticeWidth: CGFloat = 0,
        lockButtons: Bool = true, buttonsExpanded: Bool = false, viewportHandleOn: Bool = false,
        marginsButton: Bool = false, innerRect: CGRect? = nil, marginsPanelSize: CGSize = .zero,
        marginsPanelWidestWidth: CGFloat = 0, metrics m: OverlayMetrics = .standard
    ) {
        self.captureRect = captureRect
        self.innerRect = innerRect ?? captureRect
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
        let tab = CGRect(x: tabX.rounded(), y: tabY.rounded(), width: tabWidth, height: m.tabHeight)
        tabRect = tab
        // The pin with its ▾, then the margins button while it shows, the viewport, raise and pick
        // buttons, away from the tab. Collapsed, "»" stands in for the raise and pick buttons, and for
        // the viewport button unless its mode is on: the filled button is the only sign of the mode.
        // The margins button never goes behind it. Without the lock buttons, the pick button alone.
        // Right of the tab, or left of it, the pin next to the tab, when the expanded row wouldn't
        // fit on the right: decided on the expanded row, so expanding never flips sides.
        let button = m.tabHeight + m.pinGap
        let split = lockButtons ? m.tabHeight + m.pinMenuWidth + m.pinGap : 0
        let margins: [OverlayHitTarget] = lockButtons && marginsButton ? [.marginsButton] : []
        let expandedRow: [OverlayHitTarget] =
            lockButtons ? margins + [.viewportButton, .raiseViewer, .pickWindow] : [.pickWindow]
        let onRight =
            tab.maxX + m.pinGap + split + CGFloat(expandedRow.count - 1) * button + m.tabHeight
            <= screen.maxX - m.screenMargin
        buttonsOnRight = onRight
        let pinX = onRight ? tab.maxX + m.pinGap : tab.minX - split
        // The nth button after the pin's ▾, away from the tab.
        let slot = { (n: Int) -> CGRect in
            let x = onRight ? pinX + split + CGFloat(n) * button : pinX - CGFloat(n + 1) * button
            return CGRect(x: x, y: tab.minY, width: m.tabHeight, height: m.tabHeight)
        }
        let row: [OverlayHitTarget] =
            !lockButtons || buttonsExpanded
            ? expandedRow : margins + (viewportHandleOn ? [.viewportButton, .moreButtons] : [.moreButtons])
        rowButtons = row
        let rect = { (target: OverlayHitTarget) in row.firstIndex(of: target).map(slot) ?? .null }
        if lockButtons {
            pinRect = CGRect(x: pinX, y: tab.minY, width: m.tabHeight, height: m.tabHeight)
            pinMenuRect = CGRect(x: pinX + m.tabHeight, y: tab.minY, width: m.pinMenuWidth, height: m.tabHeight)
        } else {
            pinRect = .null
            pinMenuRect = .null
        }
        viewportRect = rect(.viewportButton)
        raiseRect = rect(.raiseViewer)
        pickRect = rect(.pickWindow)
        moreRect = rect(.moreButtons)
        marginsButtonRect = rect(.marginsButton)

        // Notice: left of the tab, or past the last button when the tab is at the screen's left edge.
        // With the buttons left of the tab, past the last button on that side.
        let last = slot(row.count - 1)
        var noticeX = (onRight ? tab.minX : last.minX) - m.pinGap - noticeWidth
        if onRight, noticeX < screen.minX + m.screenMargin {
            noticeX = last.maxX + m.pinGap
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

        // Position box, with the margins panel below it while the margins are on: a column whose top
        // is level with the frame's top, kept on screen: right of the frame, or left of it when the
        // right has no room. Where that covers `positionAvoiding`, the first of the frame's other side
        // and beyond the avoided rect, away from the frame, that has room and covers nothing. The box
        // and the panel keep to the column's edge next to the frame.
        let hasPanel = marginsPanelSize != .zero
        let columnWidth = hasPanel ? max(positionSize.width, marginsPanelWidestWidth) : positionSize.width
        let columnHeight = positionSize.height + (hasPanel ? m.marginsPanelGap + marginsPanelSize.height : 0)
        let columnY = Self.clamp(
            r.maxY - columnHeight, lower: screen.minY + m.screenMargin,
            upper: screen.maxY - m.screenMargin - columnHeight)
        let fits = { (x: CGFloat) in
            x >= screen.minX + m.screenMargin && x + columnWidth <= screen.maxX - m.screenMargin
        }
        let isClear = { (x: CGFloat) in
            !CGRect(x: x, y: columnY, width: columnWidth, height: columnHeight).intersects(positionAvoiding)
        }
        let rightX = r.maxX + m.positionGap
        let leftX = r.minX - m.positionGap - columnWidth
        var columnX = rightX + columnWidth <= screen.maxX - m.screenMargin ? rightX : leftX
        if !isClear(columnX) {
            // Beyond the avoided rect: on its side away from the frame.
            let avoided = positionAvoiding
            let beyond =
                avoided.midX < r.midX ? avoided.minX - m.positionGap - columnWidth : avoided.maxX + m.positionGap
            columnX = [rightX, leftX, beyond].first { fits($0) && isClear($0) } ?? columnX
        }
        columnX = Self.clamp(
            columnX, lower: screen.minX + m.screenMargin, upper: screen.maxX - m.screenMargin - columnWidth)
        // Left of the frame, the column's right edge is the one next to it.
        let alignsRight = columnX + columnWidth / 2 < r.midX
        let x = { (width: CGFloat) in (alignsRight ? columnX + columnWidth - width : columnX).rounded() }
        positionRect = CGRect(
            x: x(positionSize.width), y: (columnY + columnHeight - positionSize.height).rounded(),
            width: positionSize.width, height: positionSize.height)
        marginsPanelRect =
            hasPanel
            ? CGRect(
                x: x(marginsPanelSize.width), y: columnY.rounded(), width: marginsPanelSize.width,
                height: marginsPanelSize.height)
            : .null

        // A `.null` part adds nothing; an empty notice rect would add its origin.
        let parts = [
            tabRect, labelRect, positionRect, pinRect, pinMenuRect, viewportRect, raiseRect, pickRect, moreRect,
            marginsButtonRect, marginsPanelRect, noticeWidth > 0 ? noticeRect : .null,
        ]
        windowFrame =
            parts.reduce(r.insetBy(dx: -m.windowPadding, dy: -m.windowPadding)) {
                $0.union($1.insetBy(dx: -m.partPadding, dy: -m.partPadding))
            }
            .integral
    }

    /// Where each handle is drawn: centred on the line.
    func handleRect(_ handle: OverlayHandle, size: CGFloat) -> CGRect {
        let r = captureRect
        let x: CGFloat = handle.movesMinX ? r.minX : handle.movesMaxX ? r.maxX : r.midX
        let y: CGFloat = handle.movesMinY ? r.minY : handle.movesMaxY ? r.maxY : r.midY
        return CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size)
    }

    /// What pressing at `point` does, or `nil` when the press belongs to the app underneath. A locked
    /// frame answers its buttons and, when `lock` allows resizing, its handles, and moves only by the
    /// tab when `lock` lets it (`movesByTab`): picking a window is a command, not a drag. `fitted`: the
    /// magnet's area lies on its window's bounds (`WindowMagnet.isFitted`), and the window's own edges
    /// resize it, so the frame has no handles, and its line and band take nothing: only the buttons,
    /// the tab and the viewport handle. `viewportHandle` is the viewport handle's rect, `nil` while it
    /// isn't shown: it moves the Viewer, not the area, so it takes a press on any lock, over the
    /// handles and the tab; only the buttons keep theirs.
    func hitTarget(
        at point: CGPoint, metrics m: OverlayMetrics = .standard, lock: CaptureAreaLock? = nil,
        fitted: Bool = false, viewportHandle: CGRect? = nil
    ) -> OverlayHitTarget? {
        if let button = button(at: point) { return button }
        if viewportHandle?.contains(point) == true { return .viewportHandle }
        if let lock, !lock.allowsResize { return nil }
        if !fitted {
            for handle in OverlayHandle.allCases where handleRect(handle, size: m.handleHitSize).contains(point) {
                return .resize(handle)
            }
        }
        if tabRect.contains(point), lock?.movesByTab ?? true { return .move }
        if lock != nil || fitted { return nil }
        let outer = captureRect.insetBy(dx: -(m.lineWidth + m.bandWidth), dy: -(m.lineWidth + m.bandWidth))
        if outer.contains(point) && !captureRect.contains(point) { return .move }
        return nil
    }

    /// The tab's buttons, each half of the pin's split button on its own; the others are not buttons.
    private var buttons: [(target: OverlayHitTarget, rect: CGRect)] {
        [
            (.pin, pinRect), (.pinMenu, pinMenuRect), (.viewportButton, viewportRect), (.raiseViewer, raiseRect),
            (.pickWindow, pickRect), (.moreButtons, moreRect), (.marginsButton, marginsButtonRect),
        ]
    }

    /// The tab's button at `point`, shown, whatever the lock; `nil` over anything else.
    func button(at point: CGPoint) -> OverlayHitTarget? {
        buttons.first { $0.rect.contains(point) }?.target
    }

    /// Where the name of the tab's `button` shows, `size` large, or `nil` for a button not shown:
    /// centred on the button, `buttonNameGap` off the row on its side away from the frame — above a
    /// tab above the frame, below a tab below it or inside it — or on the other side when that leaves
    /// `screenFrame`; kept `screenMargin` inside it sideways. So it covers no button, nor the tab, nor
    /// the notice beside them, which sit level with the tab.
    func buttonNameRect(
        for button: OverlayHitTarget, size: CGSize, screenFrame screen: CGRect, metrics m: OverlayMetrics = .standard
    ) -> CGRect? {
        guard let rect = buttons.first(where: { $0.target == button })?.rect, !rect.isNull else { return nil }
        let above = tabRect.maxY + m.buttonNameGap
        let below = tabRect.minY - m.buttonNameGap - size.height
        let fitsAbove = above + size.height <= screen.maxY - m.screenMargin
        let fitsBelow = below >= screen.minY + m.screenMargin
        let y =
            tabPlacement == .above
            ? (fitsAbove || !fitsBelow ? above : below) : (fitsBelow || !fitsAbove ? below : above)
        let x = Self.clamp(
            rect.midX - size.width / 2, lower: screen.minX + m.screenMargin,
            upper: screen.maxX - m.screenMargin - size.width)
        return CGRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
    }

    /// The viewport handle for `viewedPart`, the part of the area the Viewer shows, never over it:
    /// `viewportHandleGap` outside it, above and centred on it, else below, else left, else right,
    /// wherever it first fits inside the captured rect (`innerRect`), kept within the rect along that
    /// side. `nil` when it fits nowhere: the part leaves too little of the area around it.
    func viewportHandleRect(for viewedPart: CGRect, metrics m: OverlayMetrics = .standard) -> CGRect? {
        let size = m.viewportHandleSize
        let gap = m.viewportHandleGap
        let r = innerRect
        let x = Self.clamp(viewedPart.midX - size.width / 2, lower: r.minX, upper: r.maxX - size.width)
        let y = Self.clamp(viewedPart.midY - size.height / 2, lower: r.minY, upper: r.maxY - size.height)
        let candidates = [
            CGPoint(x: x, y: viewedPart.maxY + gap),
            CGPoint(x: x, y: viewedPart.minY - gap - size.height),
            CGPoint(x: viewedPart.minX - gap - size.width, y: y),
            CGPoint(x: viewedPart.maxX + gap, y: y),
        ]
        return candidates.lazy.map { CGRect(origin: $0, size: size) }.first { r.contains($0) }
    }

    /// Whether the cursor is close enough to the frame to reveal the handles and the tab.
    func isInHoverZone(_ point: CGPoint, metrics m: OverlayMetrics = .standard) -> Bool {
        if button(at: point) != nil
            || [tabRect, labelRect, positionRect, marginsPanelRect].contains(where: { $0.contains(point) })
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

    /// `rect` grown to `minimumSize` where it is smaller, keeping its origin: a saved or picked rect.
    static func atLeastMinimum(_ rect: CGRect) -> CGRect {
        CGRect(
            origin: rect.origin,
            size: CGSize(width: max(rect.width, minimumSize.width), height: max(rect.height, minimumSize.height)))
    }

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
