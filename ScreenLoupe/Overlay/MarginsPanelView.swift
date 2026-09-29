import AppKit

/// The margins panel below the position box while the Capture Area's margins are on (docs/product.md,
/// Capture Area): collapsed, the margins in four rows as the box shows its edges; expanded, a box
/// diagram with a field for each margin around the captured size, the band's colour swatches and its
/// opacity. Drawn in the overlay's label style. Unlike the frame's other parts, it takes the mouse: a
/// press anywhere on it collapsed expands it; expanded, its « collapses it and a swatch picks the
/// band's colour. The fields apply on Return or Tab; their captions scrub (`Scrub`).
final class MarginsPanelView: NSView {
    /// What the panel shows.
    struct Content: Equatable {
        /// The margins as they apply, in points.
        var margins = CaptureMargins()
        /// Shown units per point: the display's scale when the tab shows pixels only, else 1.
        var factor: CGFloat = 1
        var unit = "pt"
        /// The captured rect's size in the same units: `880 × 502`.
        var innerSize = ""
        var color = SettingsColor.green
        /// 0...1.
        var opacity = 0.2
    }

    /// The band's colours to pick from; the last swatch opens the system colour panel.
    static let swatches: [SettingsColor] = [.green, .blue, .amber, .pink, .purple, .gray]

    /// As tall as the rows, from the title down to the opacity's.
    static let expandedSize = CGSize(
        width: expandedWidth, height: opacityRowY + fieldSize.height + padding.height)
    private static let expandedWidth: CGFloat = 196

    var content = Content() {
        didSet {
            guard content != oldValue else { return }
            showContent()
        }
    }

    /// Expanded or collapsed; the controller sizes the panel to match.
    var isExpanded = false {
        didSet {
            guard isExpanded != oldValue else { return }
            for view in expandedViews { view.isHidden = !isExpanded }
            if !isExpanded { endEditing() }
            needsDisplay = true
        }
    }

    /// A press asks to expand (`true`) or collapse the panel.
    var onExpand: ((Bool) -> Void)?
    /// A margin typed or scrubbed, in points, not yet rounded or clamped.
    var onMargin: ((CaptureMargins.Edge, CGFloat) -> Void)?
    var onColor: ((SettingsColor) -> Void)?
    /// 0...1.
    var onOpacity: ((Double) -> Void)?
    /// `isInUse` changed.
    var onInUseChange: (() -> Void)?

    /// A field is edited, a caption or the slider dragged, or its colour panel is open: the panel
    /// stays shown meanwhile.
    var isInUse: Bool {
        editing || scrubbing || slider.isTracking || colorTarget.isActive
    }

    private let fields = CaptureMargins.Edge.allCases.map { _ in PanelField() }
    private let captions = CaptureMargins.Edge.allCases.map { ScrubCaptionView(key: $0.key) }
    private let slider = PanelSlider(value: 20, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let opacityField = PanelField()
    private let colorTarget = ColorPanelTarget()
    private var closeObserver: NSObjectProtocol?
    private var editing = false { didSet { if editing != oldValue { onInUseChange?() } } }
    private var scrubbing = false { didSet { if scrubbing != oldValue { onInUseChange?() } } }

    private var expandedViews: [NSView] { fields + captions + [slider, opacityField] }

    init() {
        super.init(frame: CGRect(origin: .zero, size: Self.expandedSize))
        appearance = NSAppearance(named: .darkAqua)
        for (index, edge) in CaptureMargins.Edge.allCases.enumerated() {
            let field = fields[index]
            field.target = self
            field.action = #selector(fieldApplied(_:))
            field.delegate = self
            field.setAccessibilityLabel("\(edge.name) margin")
            let caption = captions[index]
            caption.onScrubStart = { [weak self] in
                self?.scrubbing = true
                return self?.content.margins[edge] ?? 0
            }
            caption.onScrub = { [weak self] in self?.onMargin?(edge, $0) }
            caption.onScrubEnd = { [weak self] in self?.scrubbing = false }
        }
        opacityField.target = self
        opacityField.action = #selector(opacityApplied(_:))
        opacityField.delegate = self
        opacityField.setAccessibilityLabel("Band opacity")
        slider.target = self
        slider.action = #selector(sliderMoved(_:))
        slider.isContinuous = true
        slider.controlSize = .mini
        slider.onTrackingChange = { [weak self] in self?.onInUseChange?() }
        // Tab goes round the margins in the rows' order, then to the opacity.
        let loop: [NSView] = fields + [opacityField]
        for (index, view) in loop.enumerated() {
            view.nextKeyView = loop[(index + 1) % loop.count]
        }
        for view in expandedViews {
            view.isHidden = true
            addSubview(view)
        }
        colorTarget.onChange = { [weak self] in self?.onColor?(SettingsColor($0)) }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: NSColorPanel.shared, queue: .main
        ) { [weak self] _ in
            // Once the well has let go of the panel, which it does on the same notification.
            Task { @MainActor in self?.onInUseChange?() }
        }
        layOut()
        showContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The margins turned off: nothing goes on being edited or picked for them.
    func stopUsing() {
        endEditing()
        if colorTarget.isActive { NSColorPanel.shared.close() }
    }

    /// The cursor over `point`, in the panel's coordinates: ↔ over a caption, an I-beam over a field,
    /// the pointing hand over what a click presses.
    func cursor(at point: CGPoint) -> NSCursor {
        guard isExpanded else { return .pointingHand }
        if captions.contains(where: { $0.frame.contains(point) }) { return .resizeLeftRight }
        if (fields + [opacityField]).contains(where: { $0.frame.contains(point) }) { return .iBeam }
        if chevronRect.contains(point) || swatchRects.contains(where: { $0.contains(point) }) {
            return .pointingHand
        }
        return .arrow
    }

    // MARK: Layout

    private static let padding = CGSize(width: OverlayStyle.titledPadding, height: OverlayStyle.titledPadding)
    private static let fieldSize = CGSize(width: 36, height: 16)
    private static let captionWidth: CGFloat = 10
    private static let captionGap: CGFloat = 2
    /// The window's dashed outline, the fields in its band around the captured rect.
    private static let diagramRect = CGRect(
        x: padding.width, y: OverlayStyle.titledRowsTop, width: expandedWidth - padding.width * 2, height: 100)
    private static let innerDiagramRect = diagramRect.insetBy(dx: 52, dy: 24)
    private static let separatorY = diagramRect.maxY + 6
    private static let swatchRowY = separatorY + 6
    private static let swatchSize: CGFloat = 14
    private static let opacityRowY = swatchRowY + 24

    /// « or », in the title's row.
    private var chevronRect: CGRect {
        let side = OverlayStyle.positionTitleHeight
        return CGRect(x: bounds.width - Self.padding.width - side, y: Self.padding.height, width: side, height: side)
    }

    /// The preset swatches, then the custom one, spread across the panel.
    private var swatchRects: [CGRect] {
        let count = Self.swatches.count + 1
        let diagram = Self.diagramRect
        let size = Self.swatchSize
        let step = (diagram.width - size) / CGFloat(count - 1)
        return (0..<count).map {
            CGRect(x: (diagram.minX + CGFloat($0) * step).rounded(), y: Self.swatchRowY + 2, width: size, height: size)
        }
    }

    private func layOut() {
        let d = Self.diagramRect
        let inner = Self.innerDiagramRect
        let group = Self.captionWidth + Self.captionGap + Self.fieldSize.width
        let origins: [CaptureMargins.Edge: CGPoint] = [
            .left: CGPoint(x: d.minX + 4, y: inner.midY - Self.fieldSize.height / 2),
            .top: CGPoint(x: d.midX - group / 2, y: d.minY + 4),
            .right: CGPoint(x: d.maxX - 4 - group, y: inner.midY - Self.fieldSize.height / 2),
            .bottom: CGPoint(x: d.midX - group / 2, y: d.maxY - 4 - Self.fieldSize.height),
        ]
        for (index, edge) in CaptureMargins.Edge.allCases.enumerated() {
            guard let origin = origins[edge] else { continue }
            let x = origin.x.rounded()
            let y = origin.y.rounded()
            captions[index].frame = CGRect(x: x, y: y, width: Self.captionWidth, height: Self.fieldSize.height)
            fields[index].frame = CGRect(
                x: x + Self.captionWidth + Self.captionGap, y: y, width: Self.fieldSize.width,
                height: Self.fieldSize.height)
        }
        // After the "Opacity" caption: the slider, then the field with "%" after it.
        let row = Self.opacityRowY
        slider.frame = CGRect(x: 50, y: row, width: 98, height: Self.fieldSize.height)
        opacityField.frame = CGRect(x: 152, y: row, width: 28, height: Self.fieldSize.height)
    }

    // MARK: Content

    private func showContent() {
        for (index, edge) in CaptureMargins.Edge.allCases.enumerated() where fields[index].currentEditor() == nil {
            fields[index].stringValue = shownText(content.margins[edge])
        }
        if opacityField.currentEditor() == nil {
            opacityField.stringValue = opacityText
        }
        if !slider.isTracking { slider.doubleValue = content.opacity * 100 }
        needsDisplay = true
    }

    /// A margin in the panel's units.
    private func shownText(_ points: CGFloat) -> String {
        SizeText.number(CaptureMargins.shown(points, factor: content.factor))
    }

    @objc private func fieldApplied(_ sender: PanelField) {
        guard let index = fields.firstIndex(of: sender) else { return }
        if let value = Double(sender.stringValue.trimmingCharacters(in: .whitespaces)), value.isFinite {
            onMargin?(
                CaptureMargins.Edge.allCases[index],
                CaptureMargins.points(fromShown: CGFloat(value), factor: content.factor))
        }
        // What applies, which clamping may have changed, or the value as it was.
        sender.stringValue = shownText(content.margins[CaptureMargins.Edge.allCases[index]])
    }

    @objc private func opacityApplied(_ sender: PanelField) {
        if let value = Double(sender.stringValue.trimmingCharacters(in: .whitespaces)), value.isFinite {
            onOpacity?(min(max(value, 0), 100) / 100)
        }
        sender.stringValue = opacityText
    }

    /// The band's opacity in whole percent.
    private var opacityText: String { String(Int((content.opacity * 100).rounded())) }

    @objc private func sliderMoved(_ sender: NSSlider) {
        onOpacity?(sender.doubleValue / 100)
    }

    private func endEditing() {
        guard let window, (fields + [opacityField]).contains(where: { $0.currentEditor() != nil }) else { return }
        window.makeFirstResponder(nil)
    }

    // MARK: Mouse

    /// Presses the controls AppKit doesn't: the chevron, the swatches, or collapsed, the whole panel.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard isExpanded else {
            onExpand?(true)
            return
        }
        if chevronRect.contains(point) {
            onExpand?(false)
            return
        }
        guard let index = swatchRects.firstIndex(where: { $0.contains(point) }) else { return }
        if index < Self.swatches.count {
            onColor?(Self.swatches[index])
        } else {
            // The panel hides while the app is inactive.
            NSColorPanel.shared.showsAlpha = false
            NSApp.activate()
            colorTarget.show(from: content.color.nsColor)
            onInUseChange?()
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        OverlayStyle.fillLabel(bounds)
        let padding = Self.padding
        let title = OverlayStyle.drawPanelTitle("Margins")
        drawChevron()
        guard isExpanded else {
            // The four margins, as the position box shows its edges.
            let lines = CaptureMargins.Edge.allCases.map { ($0.key, shownText(content.margins[$0])) }
            OverlayStyle.drawPositionLines(lines, in: bounds, top: OverlayStyle.titledRowsTop)
            return
        }
        let unitAttributes: [NSAttributedString.Key: Any] = [
            .font: OverlayStyle.labelFont, .foregroundColor: OverlayStyle.mutedText,
        ]
        (content.unit as NSString).draw(
            at: CGPoint(x: title.maxX + 4, y: title.minY + 1), withAttributes: unitAttributes)
        drawDiagram()
        NSColor.white.withAlphaComponent(0.25).setFill()
        CGRect(x: padding.width, y: Self.separatorY, width: bounds.width - padding.width * 2, height: 1).fill()
        drawSwatches()
        ("Opacity" as NSString).draw(
            at: CGPoint(x: padding.width, y: Self.opacityRowY + 1), withAttributes: unitAttributes)
        ("%" as NSString).draw(
            at: CGPoint(x: opacityField.frame.maxX + 2, y: Self.opacityRowY + 1), withAttributes: unitAttributes)
    }

    /// « or », white on the buttons' fill: two strokes drawn about the button's centre, since a
    /// symbol image carries uneven margins of its own.
    private func drawChevron() {
        let rect = chevronRect
        NSColor.white.withAlphaComponent(0.18).setFill()
        let radius = OverlayStyle.labelCornerRadius
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        // Each chevron 3 pt wide and 6 tall, 3 pt apart: 6 pt across in all, centred.
        let direction: CGFloat = isExpanded ? -1 : 1
        let path = NSBezierPath()
        for offset: CGFloat in [-1.5, 1.5] {
            let tipX = rect.midX + offset + direction * 1.5
            let backX = tipX - direction * 3
            path.move(to: CGPoint(x: backX, y: rect.midY - 3))
            path.line(to: CGPoint(x: tipX, y: rect.midY))
            path.line(to: CGPoint(x: backX, y: rect.midY + 3))
        }
        path.lineWidth = 1.3
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        NSColor.white.setStroke()
        path.stroke()
    }

    /// The window as a dashed outline, and inside it the captured rect in the band's colour with its
    /// size.
    private func drawDiagram() {
        let outline = NSBezierPath(roundedRect: Self.diagramRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
        outline.lineWidth = 1
        let dashes: [CGFloat] = [3, 2]
        outline.setLineDash(dashes, count: dashes.count, phase: 0)
        NSColor.white.withAlphaComponent(0.5).setStroke()
        outline.stroke()
        let inner = Self.innerDiagramRect
        let color = content.color.nsColor
        // No line, as on screen; a faint fill at least, so the rect still shows at 0 %.
        color.withAlphaComponent(max(content.opacity, 0.1)).setFill()
        inner.fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: OverlayStyle.labelFont, .foregroundColor: NSColor.white,
        ]
        let text = content.innerSize as NSString
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: CGPoint(x: (inner.midX - size.width / 2).rounded(), y: (inner.midY - size.height / 2).rounded()),
            withAttributes: attributes)
    }

    /// The presets, then the custom colour as a wheel of hues; the chosen one ringed.
    private func drawSwatches() {
        let rects = swatchRects
        let preset = Self.swatches.firstIndex(of: content.color)
        for (index, rect) in rects.enumerated() {
            if index < Self.swatches.count {
                Self.swatches[index].nsColor.setFill()
                NSBezierPath(ovalIn: rect).fill()
            } else {
                let center = CGPoint(x: rect.midX, y: rect.midY)
                let hues = 12
                for hue in 0..<hues {
                    let wedge = NSBezierPath()
                    wedge.move(to: center)
                    wedge.appendArc(
                        withCenter: center, radius: rect.width / 2, startAngle: CGFloat(hue) * 360 / CGFloat(hues),
                        endAngle: CGFloat(hue + 1) * 360 / CGFloat(hues))
                    wedge.close()
                    NSColor(hue: CGFloat(hue) / CGFloat(hues), saturation: 0.8, brightness: 1, alpha: 1).setFill()
                    wedge.fill()
                }
            }
            guard index == (preset ?? Self.swatches.count) else { continue }
            let ring = NSBezierPath(ovalIn: rect.insetBy(dx: -2.5, dy: -2.5))
            ring.lineWidth = 1.5
            NSColor.white.setStroke()
            ring.stroke()
        }
    }
}

extension MarginsPanelView: NSTextFieldDelegate {
    func controlTextDidBeginEditing(_ obj: Notification) {
        editing = true
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        editing = false
    }
}

extension CaptureMargins.Edge {
    /// Its key in the position box and the margins panel.
    fileprivate var key: String {
        switch self {
        case .left: "L"
        case .top: "T"
        case .right: "R"
        case .bottom: "B"
        }
    }

    fileprivate var name: String {
        switch self {
        case .left: "Left"
        case .top: "Top"
        case .right: "Right"
        case .bottom: "Bottom"
        }
    }
}

/// A number field in the panel: white on the buttons' fill, applying on Return, Tab or a click
/// elsewhere.
private final class PanelField: NSTextField {
    init() {
        super.init(frame: .zero)
        isBordered = false
        drawsBackground = false
        focusRingType = .none
        font = OverlayStyle.labelFont
        textColor = .white
        alignment = .center
        cell?.sendsActionOnEndEditing = true
        cell?.isScrollable = true
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
        layer?.cornerRadius = 3
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The frame's panel becomes key only if needed, which a click from another app may not go
    /// through (`CaptureOverlayView.mouseDown`): typing needs it key.
    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        super.mouseDown(with: event)
    }
}

/// The opacity slider, which says while it is dragged.
private final class PanelSlider: NSSlider {
    private(set) var isTracking = false
    var onTrackingChange: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// AppKit tracks the drag inside `mouseDown`, which returns once the mouse is up.
    override func mouseDown(with event: NSEvent) {
        isTracking = true
        onTrackingChange?()
        super.mouseDown(with: event)
        isTracking = false
        onTrackingChange?()
    }
}

/// A field's key caption, muted with a dotted underline: dragged left or right it scrubs the field's
/// value, one point per point of travel (`Scrub`), as the References panel's captions do.
private final class ScrubCaptionView: NSView {
    private let key: String
    /// The drag began: returns the value it starts from.
    var onScrubStart: (() -> CGFloat)?
    var onScrub: ((CGFloat) -> Void)?
    var onScrubEnd: (() -> Void)?
    private var start: (value: CGFloat, x: CGFloat)?

    init(key: String) {
        self.key = key
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        NSCursor.resizeLeftRight.set()
        // In screen points: the frame's window can move while the margin changes.
        start = (onScrubStart?() ?? 0, NSEvent.mouseLocation.x)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let flags = event.modifierFlags
        let value = Scrub.value(
            from: Double(start.value), travel: Double(NSEvent.mouseLocation.x - start.x), step: 1,
            shift: flags.contains(.shift), option: flags.contains(.option))
        onScrub?(CGFloat(value))
    }

    override func mouseUp(with event: NSEvent) {
        guard start != nil else { return }
        start = nil
        onScrubEnd?()
    }

    override func draw(_ dirtyRect: NSRect) {
        let muted = OverlayStyle.mutedText
        let attributes: [NSAttributedString.Key: Any] = [.font: OverlayStyle.labelFont, .foregroundColor: muted]
        let text = key as NSString
        let size = text.size(withAttributes: attributes)
        let y = ((bounds.height - size.height) / 2).rounded()
        text.draw(at: CGPoint(x: 0, y: y), withAttributes: attributes)
        let underline = NSBezierPath()
        underline.move(to: CGPoint(x: 0, y: y + size.height - 0.5))
        underline.line(to: CGPoint(x: size.width, y: y + size.height - 0.5))
        underline.lineWidth = 1
        let dashes: [CGFloat] = [1, 2]
        underline.setLineDash(dashes, count: dashes.count, phase: 0)
        muted.setStroke()
        underline.stroke()
    }
}
