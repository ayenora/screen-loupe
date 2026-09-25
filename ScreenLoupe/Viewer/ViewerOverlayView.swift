import AppKit

/// Drawn over the magnified image: the pointer on the pixel under the real cursor inside the
/// Capture Area, which the capture itself doesn't show (docs/product.md, Crosshair and cursor).
///
/// Only for the real cursor: when the mouse is over the Viewer, the mouse pointer already marks the
/// spot. As a crosshair, lines run across the whole view through that pixel and a box outlines it;
/// as a cursor, an arrow at its usual size points at the outlined pixel. White under the colour
/// (orange by default) reads on any content. With the original cursor in the capture nothing is
/// drawn: the capture has it. Never takes the mouse.
final class ViewerOverlayView: NSView {
    private let zoomPan: ZoomPanController
    private let inspector: PixelInspector
    var showsCrosshair = true { didSet { if showsCrosshair != oldValue { needsDisplay = true } } }
    var pointerStyle = PointerStyle.crosshair { didSet { if pointerStyle != oldValue { needsDisplay = true } } }
    var color = SettingsColor.orange.nsColor { didSet { if color != oldValue { needsDisplay = true } } }
    /// The corner ruler, drawn over everything else.
    var ruler: RulerController?
    /// The selected reference layer gets a frame and corner handles for scaling.
    var references: ReferencesController?
    /// The Select tool's selection and an Option-drag's region.
    var selection: SelectionController?
    /// Source pixels per point of the captured display, for the ruler's lengths in points.
    var sourceScale: () -> CGFloat = { 1 }
    /// The Viewer's drawable pixels per point (`MTKView.drawableScale`): zoom and pan are in drawable
    /// pixels, this view draws in points.
    var drawableScale: () -> CGFloat = { 1 }

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
    }

    private func drawCrosshair(drawableScale: CGFloat) {
        guard showsCrosshair, pointerStyle != .capturedCursor, let probe = inspector.probe,
            probe.source == .captureArea
        else { return }
        let pixel = Self.points(
            zoomPan.state.imageRect(origin: CGPoint(x: probe.x, y: probe.y), size: CGSize(width: 1, height: 1)),
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
        let rect = Self.points(zoomPan.state.imageRect(origin: layer.origin, size: layer.frame.size), scale: scale)
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
            Self.drawChip("\(Int(region.width)) × \(Int(region.height)) px · let go to copy", below: rect, in: bounds)
            return
        }
        guard selection.isToolOn, let rect = selection.selection else { return }
        let state = zoomPan.state
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
        Self.drawChip(PixelSelection.label(rect), below: placed, in: bounds)
    }

    private static let chipAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.white,
    ]

    /// A dark label under `rect`'s bottom-left corner, or over its top when there is no room below.
    private static func drawChip(_ text: String, below rect: CGRect, in bounds: CGRect) {
        let size = (text as NSString).size(withAttributes: chipAttributes)
        let chipSize = CGSize(width: (size.width + 14).rounded(.up), height: (size.height + 4).rounded(.up))
        var origin = CGPoint(x: rect.minX, y: rect.maxY + 6)
        if origin.y + chipSize.height > bounds.maxY { origin.y = rect.minY - 6 - chipSize.height }
        origin.x = min(max(origin.x, bounds.minX + 4), bounds.maxX - chipSize.width - 4)
        let chip = CGRect(origin: CGPoint(x: origin.x.rounded(), y: origin.y.rounded()), size: chipSize)
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
        let step = zoomPan.state.zoom / scale

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

        let sourceScale = sourceScale()
        let horizontalText = Self.length(abs(arms.width), sourceScale: sourceScale)
        let verticalText = Self.length(abs(arms.height), sourceScale: sourceScale)
        let horizontalSize = Self.pillSize(horizontalText)
        let verticalSize = Self.pillSize(verticalText)
        // Off the pixels the lengths are approximate: dimmed until the ruler is on them.
        context.saveGState()
        if !drawn.isOnPixels { context.setAlpha(0.5) }
        Self.drawPill(
            horizontalText,
            center: CGPoint(
                x: (corner.x + horizontalEnd.x) / 2,
                y: corner.y + (arms.height > 0 ? -1 : 1) * (horizontalSize.height / 2 + 9)))
        Self.drawPill(
            verticalText,
            center: CGPoint(
                x: corner.x + (arms.width > 0 ? -1 : 1) * (verticalSize.width / 2 + 9),
                y: (corner.y + verticalEnd.y) / 2))
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

    /// `32 px · 16 pt`, or `32 px` when a pixel is a point.
    private static func length(_ pixels: CGFloat, sourceScale: CGFloat) -> String {
        let px = "\(Int(pixels)) px"
        guard sourceScale != 1 else { return px }
        let points = pixels / sourceScale
        let text = points == points.rounded() ? "\(Int(points))" : String(format: "%.1f", Double(points))
        return "\(px) · \(text) pt"
    }

    private static let pillAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11, weight: .bold), .foregroundColor: NSColor.white,
    ]

    private static func pillSize(_ text: String) -> CGSize {
        let size = (text as NSString).size(withAttributes: pillAttributes)
        return CGSize(width: size.width.rounded(.up) + 12, height: 18)
    }

    private static func drawPill(_ text: String, center: CGPoint) {
        let size = pillSize(text)
        let rect = CGRect(
            x: (center.x - size.width / 2).rounded(), y: (center.y - size.height / 2).rounded(), width: size.width,
            height: size.height)
        rulerColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
        let textSize = (text as NSString).size(withAttributes: pillAttributes)
        (text as NSString).draw(
            at: CGPoint(x: rect.minX + 6, y: rect.minY + ((size.height - textSize.height) / 2).rounded()),
            withAttributes: pillAttributes)
    }
}

/// Over the image while the view is frozen or a delayed freeze counts down (docs/product.md, Freeze
/// frame): an accent border around the image area and a chip at its top — solid and "Frozen · Space
/// to resume" when frozen, dashed with a shrinking ring and the seconds left while counting down.
/// After a freeze from another app a second chip at the bottom says how it happened. A recent
/// capture shown in place of the live view gets a purple border and its own chip (docs/product.md,
/// Recent Captures). Never in Copy View, which draws the frame itself.
final class FrozenIndicatorView: NSView {
    enum State: Equatable {
        case hidden
        /// `hint`: how it was frozen, after the global shortcut.
        case frozen(hint: String?)
        /// A delayed freeze happens at `deadline`, `total` seconds after it was asked for.
        case countdown(deadline: Date, total: TimeInterval)
        /// A recent capture shows; `label` says which.
        case capture(label: String)

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

    private static let frozenText = "Frozen · Space to resume" as NSString
    private static let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11.5, weight: .semibold), .foregroundColor: NSColor.white,
    ]
    private static let digitAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold), .foregroundColor: NSColor.white,
    ]
    private static let darkFill = NSColor(srgbRed: 28 / 255, green: 28 / 255, blue: 30 / 255, alpha: 0.9)
    /// Darker than the border's system purple, so the white text on it reads.
    private static let captureChip = NSColor(srgbRed: 155 / 255, green: 63 / 255, blue: 209 / 255, alpha: 1)

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
        }
    }

    private func drawChip(_ text: NSString, color: NSColor) {
        let size = text.size(withAttributes: Self.attributes)
        let chip = CGRect(
            x: (bounds.midX - size.width / 2 - 10).rounded(), y: 12, width: (size.width + 20).rounded(.up),
            height: (size.height + 10).rounded(.up))
        color.setFill()
        NSBezierPath(roundedRect: chip, xRadius: 8, yRadius: 8).fill()
        text.draw(at: CGPoint(x: chip.minX + 10, y: chip.minY + 5), withAttributes: Self.attributes)
    }

    private func drawBorder(dashed: Bool, color: NSColor = .systemBlue) {
        color.setStroke()
        let border = NSBezierPath(rect: bounds.insetBy(dx: 1.5, dy: 1.5))
        border.lineWidth = 3
        if dashed { border.setLineDash([10, 6], count: 2, phase: 0) }
        border.stroke()
    }

    /// A dark pill at the top: a ring that empties as the seconds run out, the seconds left in it,
    /// and "Freezing in 2 s · Esc to cancel".
    private func drawCountdown(remaining: TimeInterval, total: TimeInterval) {
        let seconds = Int(remaining.rounded(.up))
        let text = "Freezing in \(seconds) s · Esc to cancel" as NSString
        let size = text.size(withAttributes: Self.attributes)
        let ring: CGFloat = 26
        let pill = CGRect(
            x: (bounds.midX - (6 + ring + 8 + size.width + 14) / 2).rounded(), y: 10,
            width: (6 + ring + 8 + size.width + 14).rounded(.up), height: ring + 12)
        Self.darkFill.setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()

        let center = CGPoint(x: pill.minX + 6 + ring / 2, y: pill.midY)
        let radius = (ring - 2.5) / 2
        let track = NSBezierPath(
            ovalIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        track.lineWidth = 2.5
        NSColor.systemBlue.withAlphaComponent(0.25).setStroke()
        track.stroke()
        // Flipped view: growing angles run clockwise, from the top.
        let fraction = total > 0 ? CGFloat(remaining / total) : 0
        let arc = NSBezierPath()
        arc.appendArc(
            withCenter: center, radius: radius, startAngle: -90, endAngle: -90 + 360 * fraction, clockwise: false)
        arc.lineWidth = 2.5
        NSColor.systemBlue.setStroke()
        arc.stroke()
        let digits = "\(seconds)" as NSString
        let digitSize = digits.size(withAttributes: Self.digitAttributes)
        digits.draw(
            at: CGPoint(x: (center.x - digitSize.width / 2).rounded(), y: (center.y - digitSize.height / 2).rounded()),
            withAttributes: Self.digitAttributes)
        text.draw(
            at: CGPoint(x: pill.minX + 6 + ring + 8, y: (pill.midY - size.height / 2).rounded()),
            withAttributes: Self.attributes)
    }

    /// "Frozen by F13 from Simulator — let go of the mouse, then zoom, pan, copy" at the bottom.
    private func drawHint(_ hint: String) {
        let text = hint as NSString
        let size = text.size(withAttributes: Self.attributes)
        let pill = CGRect(
            x: (bounds.midX - size.width / 2 - 12).rounded(), y: (bounds.maxY - 20 - size.height - 12).rounded(),
            width: (size.width + 24).rounded(.up), height: (size.height + 12).rounded(.up))
        Self.darkFill.setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
        text.draw(at: CGPoint(x: pill.minX + 12, y: pill.minY + 6), withAttributes: Self.attributes)
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
