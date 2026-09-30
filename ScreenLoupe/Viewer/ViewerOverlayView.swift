import AppKit

/// Drawn over the magnified image: the pointer on the pixel under the real cursor inside the
/// Capture Area, which the capture itself doesn't show.
///
/// Only for the real cursor: when the mouse is over the Viewer, the mouse pointer already marks the
/// spot. As a crosshair, lines run across the whole view through that pixel and a box outlines it;
/// as a cursor, an arrow at its usual size points at the outlined pixel. White under the colour
/// (orange by default) reads on any content. With the original cursor in the capture nothing is
/// drawn: the capture has it. Never takes the mouse. Everything here is placed over the presented
/// view (`ZoomPanController.presented`), as the image is drawn during a zoom glide.
final class ViewerOverlayView: NSView {
    private let zoomPan: ZoomPanController
    private let inspector: PixelInspector
    var showsCrosshair = true { didSet { if showsCrosshair != oldValue { needsDisplay = true } } }
    var pointerStyle = PointerStyle.crosshair { didSet { if pointerStyle != oldValue { needsDisplay = true } } }
    var color = SettingsColor.orange.nsColor { didSet { if color != oldValue { needsDisplay = true } } }
    /// The corner ruler, drawn over everything but the selection; the Selection Ruler, over it.
    var ruler: RulerController?
    /// The selected reference layer gets a frame and corner handles for scaling.
    var references: ReferencesController?
    /// The Select tool's selection and an Option-drag's region.
    var selection: SelectionController?
    /// The freeze's hint at the bottom while it shows (`FrozenIndicatorView.shownHint`): the
    /// Selection Ruler's hint goes above it (`ViewerHints`).
    var freezeHint: () -> String? = { nil }
    /// The Viewer's drawable pixels per point (`MTKView.drawableScale`): zoom and pan are in drawable
    /// pixels, this view draws in points.
    var drawableScale: () -> CGFloat = { 1 }
    /// The shown frame's pixels per point (`FrameLayout.scale`, 1 for an image file): the
    /// selection's badge gives its size in points too.
    var sourceScale: () -> CGFloat = { 1 }

    init(zoomPan: ZoomPanController, inspector: PixelInspector) {
        self.zoomPan = zoomPan
        self.inspector = inspector
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let drawableScale = drawableScale()
        drawSelectedReference(drawableScale: drawableScale)
        drawCrosshair(drawableScale: drawableScale)
        drawRuler(drawableScale: drawableScale)
        drawSelection(drawableScale: drawableScale)
        drawSelectionRuler(drawableScale: drawableScale)
    }

    private func drawCrosshair(drawableScale: CGFloat) {
        guard showsCrosshair, pointerStyle != .capturedCursor, let probe = inspector.probe,
            probe.source == .captureArea
        else { return }
        let pixel = Self.points(
            zoomPan.presented.imageRect(origin: CGPoint(x: probe.x, y: probe.y), size: CGSize(width: 1, height: 1)),
            scale: drawableScale)
        let center = CGPoint(x: pixel.midX, y: pixel.midY)
        if pointerStyle == .cursor { return drawCursor(at: center, pixel: pixel) }

        let lines = NSBezierPath()
        lines.move(to: CGPoint(x: bounds.minX, y: center.y))
        lines.line(to: CGPoint(x: bounds.maxX, y: center.y))
        lines.move(to: CGPoint(x: center.x, y: bounds.minY))
        lines.line(to: CGPoint(x: center.x, y: bounds.maxY))
        let box = NSBezierPath(rect: pixel.insetBy(dx: -1, dy: -1))

        NSColor.white.withAlphaComponent(0.85).setStroke()
        lines.lineWidth = 3
        lines.stroke()
        box.lineWidth = 3
        box.stroke()
        color.setStroke()
        lines.lineWidth = 1
        lines.stroke()
        box.lineWidth = 1.5
        box.stroke()
    }

    /// The system arrow at its usual size, its tip on the centre of the outlined pixel.
    private func drawCursor(at tip: CGPoint, pixel: CGRect) {
        let box = NSBezierPath(rect: pixel.insetBy(dx: -1, dy: -1))
        NSColor.white.withAlphaComponent(0.85).setStroke()
        box.lineWidth = 3
        box.stroke()
        color.setStroke()
        box.lineWidth = 1.5
        box.stroke()
        let arrow = NSCursor.arrow
        let size = arrow.image.size
        // The hot spot is measured from the image's top-left corner, as this view's y runs.
        arrow.image.draw(
            in: CGRect(x: tip.x - arrow.hotSpot.x, y: tip.y - arrow.hotSpot.y, width: size.width, height: size.height),
            from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    // MARK: References

    private func drawSelectedReference(drawableScale scale: CGFloat) {
        guard let references, let layer = references.stack.selected, references.isActive, layer.isVisible else {
            return
        }
        let picture = references.pictureRect(of: layer)
        let rect = Self.points(zoomPan.presented.imageRect(origin: picture.origin, size: picture.size), scale: scale)
        let outline = NSBezierPath(rect: rect.insetBy(dx: -0.5, dy: -0.5))
        outline.lineWidth = 1
        NSColor.systemBlue.setStroke()
        outline.stroke()
        for handle in references.handles(scale: scale) {
            let box = Self.points(handle.rect, scale: scale)
            NSColor.white.setFill()
            box.fill()
            NSColor.systemBlue.setStroke()
            let border = NSBezierPath(rect: box.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1
            border.stroke()
        }
    }

    /// A rect in drawable pixels as this view's points.
    private static func points(_ rect: CGRect, scale: CGFloat) -> CGRect {
        CGRect(x: rect.minX / scale, y: rect.minY / scale, width: rect.width / scale, height: rect.height / scale)
    }

    // MARK: Selection

    /// The Select tool's selection, solid, with its handles and its size and place; or an
    /// Option-drag's region, dashed, with the size of the image it copies.
    private func drawSelection(drawableScale scale: CGFloat) {
        guard let selection else { return }
        if let region = selection.region {
            let rect = Self.points(region, scale: scale)
            let outline = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            outline.lineWidth = 3
            NSColor.black.withAlphaComponent(0.7).setStroke()
            outline.stroke()
            outline.lineWidth = 1
            outline.setLineDash([4, 3], count: 2, phase: 0)
            NSColor.white.setStroke()
            outline.stroke()
            Self.drawChip("\(Int(region.width)) × \(Int(region.height)) px · let go to copy", for: rect, in: bounds)
            return
        }
        guard selection.isToolOn, let rect = selection.selection else { return }
        let state = zoomPan.presented
        let placed = Self.points(state.imageRect(origin: rect.origin, size: rect.size), scale: scale)
        NSColor.systemBlue.withAlphaComponent(0.08).setFill()
        placed.fill()
        let outline = NSBezierPath(rect: placed.insetBy(dx: 0.5, dy: 0.5))
        outline.lineWidth = 1
        NSColor.systemBlue.setStroke()
        outline.stroke()
        let side = SelectionController.handleSize
        for handle in SelectionHandle.allCases {
            let center = PixelSelection.handlePoint(handle, of: rect, in: state)
            let box = CGRect(x: center.x / scale - side / 2, y: center.y / scale - side / 2, width: side, height: side)
            NSColor.white.setFill()
            box.fill()
            NSColor.systemBlue.setStroke()
            let border = NSBezierPath(rect: box.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1
            border.stroke()
        }
        // Out of the Selection Ruler's way.
        let lengths = ruler?.measured(rect, placed: placed, bounds: bounds)
        Self.drawChip(
            PixelSelection.label(rect, sourceScale: sourceScale()), for: placed, in: bounds,
            ruler: lengths.map { ($0.width, $0.height) })
    }

    private static let chipAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.white,
    ]

    /// A dark label by `rect`, as `SelectionRuler.badgeRect` places it: under its bottom-left corner,
    /// else over its top, else inside it; clear of the Selection Ruler's `ruler` lines.
    private static func drawChip(
        _ text: String, for rect: CGRect, in bounds: CGRect,
        ruler: (width: SelectionRuler.Line, height: SelectionRuler.Line)? = nil
    ) {
        let size = (text as NSString).size(withAttributes: chipAttributes)
        let chipSize = CGSize(width: (size.width + 14).rounded(.up), height: (size.height + 4).rounded(.up))
        let chip = SelectionRuler.badgeRect(size: chipSize, for: rect, in: bounds, ruler: ruler)
        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: chip, xRadius: 5, yRadius: 5).fill()
        (text as NSString).draw(at: CGPoint(x: chip.minX + 7, y: chip.minY + 2), withAttributes: chipAttributes)
    }

    // MARK: Ruler

    static let rulerColor = NSColor(srgbRed: 1, green: 0.176, blue: 0.584, alpha: 1)

    private func drawRuler(drawableScale scale: CGFloat) {
        guard let ruler, let rulerState = ruler.ruler, let drawn = ruler.drawn(scale: scale),
            let context = NSGraphicsContext.current?.cgContext
        else { return }
        func point(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x / scale, y: p.y / scale) }
        let corner = point(drawn.corner)
        let horizontalEnd = point(drawn.horizontalEnd)
        let verticalEnd = point(drawn.verticalEnd)
        let arms = drawn.placement.arms

        // On hover, the band that moves an unpinned ruler, as around the Capture Area's line.
        if ruler.isHovered, !rulerState.isPinned {
            let reach = RulerController.lineReach
            Self.rulerColor.withAlphaComponent(0.22).setFill()
            CGRect(
                x: min(corner.x, horizontalEnd.x) - reach, y: corner.y - reach,
                width: abs(horizontalEnd.x - corner.x) + reach * 2, height: reach * 2
            ).fill()
            CGRect(
                x: corner.x - reach, y: min(corner.y, verticalEnd.y) - reach, width: reach * 2,
                height: abs(verticalEnd.y - corner.y) + reach * 2
            ).fill()
        }
        // Points per source pixel.
        let step = zoomPan.presented.zoom / scale

        let path = NSBezierPath()
        path.move(to: horizontalEnd)
        path.line(to: corner)
        path.line(to: verticalEnd)
        // Ticks on the outer side of each arm: every pixel when they are 4 pt apart, longer every 10.
        if step >= 4 {
            let up: CGFloat = arms.height > 0 ? -1 : 1
            let left: CGFloat = arms.width > 0 ? -1 : 1
            for index in 1..<Int(abs(arms.width)) {
                let x = corner.x + CGFloat(index) * step * (arms.width < 0 ? -1 : 1)
                path.move(to: CGPoint(x: x, y: corner.y))
                path.line(to: CGPoint(x: x, y: corner.y + up * (index % 10 == 0 ? 6 : 3)))
            }
            for index in 1..<Int(abs(arms.height)) {
                let y = corner.y + CGFloat(index) * step * (arms.height < 0 ? -1 : 1)
                path.move(to: CGPoint(x: corner.x, y: y))
                path.line(to: CGPoint(x: corner.x + left * (index % 10 == 0 ? 6 : 3), y: y))
            }
        }
        NSColor.white.withAlphaComponent(0.9).setStroke()
        path.lineWidth = 3.5
        path.stroke()
        Self.rulerColor.setStroke()
        path.lineWidth = 1.5
        path.stroke()

        var handles = [horizontalEnd, verticalEnd]
        if !rulerState.isPinned { handles.append(corner) }
        for center in handles {
            let circle = NSBezierPath(
                ovalIn: CGRect(
                    x: center.x - RulerController.handleRadius, y: center.y - RulerController.handleRadius,
                    width: RulerController.handleRadius * 2, height: RulerController.handleRadius * 2))
            NSColor.white.setFill()
            circle.fill()
            Self.rulerColor.setStroke()
            circle.lineWidth = 2
            circle.stroke()
        }

        // Off the pixels the lengths are approximate: dimmed until the ruler is on them.
        context.saveGState()
        if !drawn.isOnPixels { context.setAlpha(0.5) }
        Self.drawPill(drawn.horizontalLabel.text, in: Self.points(drawn.horizontalLabel.rect, scale: scale))
        Self.drawPill(drawn.verticalLabel.text, in: Self.points(drawn.verticalLabel.rect, scale: scale))
        context.restoreGState()

        if ruler.isHovered {
            let pin = point(drawn.pin)
            let radius = RulerController.pinRadius
            let circle = NSBezierPath(
                ovalIn: CGRect(x: pin.x - radius, y: pin.y - radius, width: radius * 2, height: radius * 2))
            (rulerState.isPinned ? Self.rulerColor : NSColor.white).setFill()
            circle.fill()
            Self.rulerColor.setStroke()
            circle.lineWidth = 1.5
            circle.stroke()
            let configuration = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [rulerState.isPinned ? .white : Self.rulerColor]))
            if let image = NSImage(
                systemSymbolName: rulerState.isPinned ? "pin.fill" : "pin",
                accessibilityDescription: rulerState.isPinned ? "Unpin ruler" : "Pin ruler")?
                .withSymbolConfiguration(configuration)
            {
                image.draw(
                    in: CGRect(
                        x: pin.x - image.size.width / 2, y: pin.y - image.size.height / 2, width: image.size.width,
                        height: image.size.height))
            }
        }
    }

    /// A length label; `rect` in points.
    private static func drawPill(_ label: String, in rect: CGRect) {
        rulerColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
        let text = label as NSString
        let textSize = text.size(withAttributes: RulerController.labelAttributes)
        text.draw(
            at: CGPoint(
                x: rect.minX + RulerController.labelPadding,
                y: rect.minY + ((rect.height - textSize.height) / 2).rounded()),
            withAttributes: RulerController.labelAttributes)
    }

    // MARK: Selection Ruler

    /// The Selection Ruler: the selection's width and height as dimension lines, drawn as the corner
    /// ruler is, over the presented view like the selection. Without a selection, a hint at the
    /// bottom says how to get one.
    private func drawSelectionRuler(drawableScale scale: CGFloat) {
        guard let ruler, ruler.measuresSelection, let selection, selection.region == nil else { return }
        guard selection.isToolOn, let rect = selection.selection else {
            let hint =
                selection.isToolOn ? "Draw a selection to measure it" : "Turn on Select (⌘E) to measure a selection"
            let hints = [freezeHint(), hint].compactMap { $0 }
            guard let rect = ViewerHints.rects(sizes: hints.map(FrozenIndicatorView.hintSize), in: bounds).last else {
                return
            }
            return FrozenIndicatorView.drawHint(hint, in: rect)
        }
        let placed = Self.points(zoomPan.presented.imageRect(origin: rect.origin, size: rect.size), scale: scale)
        guard let measured = ruler.measured(rect, placed: placed, bounds: bounds) else { return }
        let path = NSBezierPath()
        let reach = SelectionRuler.markReach
        for line in [measured.width, measured.height] {
            path.move(to: line.start)
            path.line(to: line.end)
            let isHorizontal = line.start.y == line.end.y
            for end in [line.start, line.end] {
                path.move(to: CGPoint(x: end.x - (isHorizontal ? 0 : reach), y: end.y - (isHorizontal ? reach : 0)))
                path.line(to: CGPoint(x: end.x + (isHorizontal ? 0 : reach), y: end.y + (isHorizontal ? reach : 0)))
            }
        }
        NSColor.white.withAlphaComponent(0.9).setStroke()
        path.lineWidth = 3.5
        path.stroke()
        Self.rulerColor.setStroke()
        path.lineWidth = 1.5
        path.stroke()
        Self.drawPill(measured.widthText, in: measured.width.label)
        Self.drawPill(measured.heightText, in: measured.height.label)
    }
}

/// Over the image while the view is frozen or a delayed freeze counts down: an accent border around the image area and
/// a chip at its top — solid and "Frozen · Space
/// to resume" when frozen, dashed with a shrinking ring and the seconds left while counting down.
/// After a freeze from another app a second chip at the bottom says how it happened. A recent
/// capture shown in place of the live view gets a purple border and its own chip. The colour vision
/// simulation gets an orange border and a chip of its own, stacked under another indicator that
/// shows (`ViewerIndicators`). Never in Copy View, which draws the frame itself.
final class FrozenIndicatorView: NSView {
    enum State: Equatable {
        case hidden
        /// `hint`: how it was frozen, after the global shortcut.
        case frozen(hint: String?)
        /// A delayed freeze happens at `deadline`, `total` seconds after it was asked for.
        case countdown(deadline: Date, total: TimeInterval)
        /// A recent capture shows; `label` says which.
        case capture(label: String)
        /// A colour vision is simulated; `label` says which.
        case simulation(label: String)

        var isFrozen: Bool {
            if case .frozen = self { return true }
            return false
        }
    }

    var state = State.hidden {
        didSet {
            guard state != oldValue else { return }
            isHidden = state == .hidden
            needsDisplay = true
            ticker?.invalidate()
            ticker = nil
            if case .countdown = state {
                ticker = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.needsDisplay = true }
                }
            }
        }
    }

    private var ticker: Timer?

    /// Where the simulation's chip and border go (`ViewerIndicators`): the chip's top, and the
    /// border's inset from the edge.
    var stacking = (top: ViewerIndicators.top, inset: CGFloat(0)) {
        didSet { needsDisplay = true }
    }

    private static let frozenText = "Frozen · Space to resume" as NSString
    static let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11.5, weight: .semibold), .foregroundColor: NSColor.white,
    ]
    static let darkFill = NSColor(srgbRed: 28 / 255, green: 28 / 255, blue: 30 / 255, alpha: 0.9)
    /// Darker than the border's system purple, so the white text on it reads.
    private static let captureChip = NSColor(srgbRed: 155 / 255, green: 63 / 255, blue: 209 / 255, alpha: 1)
    /// Darker than the border's system orange, likewise.
    private static let simulationChip = NSColor(srgbRed: 190 / 255, green: 80 / 255, blue: 0, alpha: 1)

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        switch state {
        case .hidden:
            return
        case .frozen(let hint):
            drawBorder(dashed: false)
            drawChip(Self.frozenText, color: .systemBlue)
            if let hint { drawHint(hint) }
        case .countdown(let deadline, let total):
            drawBorder(dashed: true)
            drawCountdown(remaining: max(0, deadline.timeIntervalSinceNow), total: total)
        case .capture(let label):
            drawBorder(dashed: false, color: .systemPurple)
            drawChip(label as NSString, color: Self.captureChip)
        case .simulation(let label):
            drawBorder(dashed: false, color: .systemOrange, inset: stacking.inset)
            drawChip(label as NSString, color: Self.simulationChip, top: stacking.top)
        }
    }

    /// The bottom of the chip or pill at the top while one shows, for the simulation's to stack
    /// under; `nil` while none does.
    var chipBottom: CGFloat? {
        guard !isHidden, alphaValue > 0 else { return nil }
        switch state {
        case .hidden: return nil
        case .frozen: return ViewerIndicators.top + Self.chipHeight(Self.frozenText)
        case .countdown: return 10 + CountdownPill.freeze.ring + 2 * CountdownPill.freeze.inset
        case .capture(let label), .simulation(let label):
            return ViewerIndicators.top + Self.chipHeight(label as NSString)
        }
    }

    private static func chipHeight(_ text: NSString) -> CGFloat {
        (text.size(withAttributes: attributes).height + 10).rounded(.up)
    }

    private func drawChip(_ text: NSString, color: NSColor, top: CGFloat = ViewerIndicators.top) {
        let size = text.size(withAttributes: Self.attributes)
        let chip = CGRect(
            x: (bounds.midX - size.width / 2 - 10).rounded(), y: top, width: (size.width + 20).rounded(.up),
            height: Self.chipHeight(text))
        color.setFill()
        NSBezierPath(roundedRect: chip, xRadius: 8, yRadius: 8).fill()
        text.draw(at: CGPoint(x: chip.minX + 10, y: chip.minY + 5), withAttributes: Self.attributes)
    }

    private func drawBorder(dashed: Bool, color: NSColor = .systemBlue, inset: CGFloat = 0) {
        color.setStroke()
        let half = ViewerIndicators.borderWidth / 2
        let border = NSBezierPath(rect: bounds.insetBy(dx: inset + half, dy: inset + half))
        border.lineWidth = ViewerIndicators.borderWidth
        if dashed { border.setLineDash([10, 6], count: 2, phase: 0) }
        border.stroke()
    }

    /// A dark pill at the top: a ring that empties as the seconds run out, the seconds left in it,
    /// and "Freezing in 2 s · Esc to cancel".
    private func drawCountdown(remaining: TimeInterval, total: TimeInterval) {
        let seconds = Int(remaining.rounded(.up))
        let text = "Freezing in \(seconds) s · Esc to cancel"
        let pill = CountdownPill.freeze
        let size = pill.size(for: text)
        pill.draw(
            text, seconds: seconds, fraction: total > 0 ? CGFloat(remaining / total) : 0,
            in: CGRect(origin: CGPoint(x: (bounds.midX - pill.exactWidth(for: text) / 2).rounded(), y: 10), size: size))
    }

    /// "Frozen by F13 from Simulator — let go of the mouse, then zoom, pan, copy" at the bottom,
    /// lowest of the hints there (`ViewerHints`).
    private func drawHint(_ hint: String) {
        guard let rect = ViewerHints.rects(sizes: [Self.hintSize(hint)], in: bounds).first else { return }
        Self.drawHint(hint, in: rect)
    }

    /// The hint at the bottom while it shows; `nil` while it doesn't.
    var shownHint: String? {
        guard !isHidden, alphaValue > 0, case .frozen(let hint?) = state else { return nil }
        return hint
    }

    /// A bottom hint's dark pill for `hint`.
    static func hintSize(_ hint: String) -> CGSize {
        ViewerHints.pillSize(textSize: (hint as NSString).size(withAttributes: attributes))
    }

    /// A bottom hint in its dark pill at `rect`: this view's, and the Selection Ruler's over the image.
    static func drawHint(_ hint: String, in rect: CGRect) {
        darkFill.setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
        (hint as NSString).draw(
            at: CGPoint(x: rect.minX + ViewerHints.padding.width, y: rect.minY + ViewerHints.padding.height),
            withAttributes: attributes)
    }
}

extension NSCursor {
    /// An eyedropper with a white halo, tip at the bottom left, for picking colours in the Viewer.
    @MainActor
    static let eyedropper: NSCursor = {
        let size = NSSize(width: 22, height: 22)
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        guard
            let symbol = NSImage(systemSymbolName: "eyedropper", accessibilityDescription: "Eyedropper")?
                .withSymbolConfiguration(configuration)
        else { return .crosshair }

        func tinted(_ color: NSColor) -> NSImage {
            NSImage(size: symbol.size, flipped: false) { rect in
                symbol.draw(in: rect)
                color.set()
                rect.fill(using: .sourceAtop)
                return true
            }
        }
        let black = tinted(.black)
        let white = tinted(.white)
        let image = NSImage(size: size, flipped: false) { _ in
            let origin = CGPoint(x: 2, y: 2)
            for dx in [-1.0, 0, 1] {
                for dy in [-1.0, 0, 1] where dx != 0 || dy != 0 {
                    white.draw(
                        at: CGPoint(x: origin.x + dx, y: origin.y + dy), from: .zero, operation: .sourceOver,
                        fraction: 1)
                }
            }
            black.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        // The hot spot is measured from the image's top-left corner: the tip, bottom left.
        return NSCursor(image: image, hotSpot: NSPoint(x: 3, y: size.height - 3))
    }()
}
