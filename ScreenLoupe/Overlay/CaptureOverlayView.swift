import AppKit

@MainActor
protocol CaptureOverlayViewDelegate: AnyObject {
    /// Points are in AppKit global coordinates.
    func overlayView(_ view: CaptureOverlayView, hitTargetAt point: CGPoint) -> OverlayHitTarget?
    func overlayView(_ view: CaptureOverlayView, mouseDownAt point: CGPoint)
    func overlayView(_ view: CaptureOverlayView, mouseDraggedTo point: CGPoint)
    func overlayViewMouseUp(_ view: CaptureOverlayView)
    /// Returns whether the key was handled.
    func overlayView(_ view: CaptureOverlayView, keyDown event: NSEvent) -> Bool
}

/// Draws the Capture Area frame and turns mouse and key events into delegate calls.
///
/// The line is always drawn. The band, the handles, the tab and the position box fade in on hover;
/// the muted size label shows at rest. A pinned frame shows no band or handles. Subviews never take
/// the mouse, so every event lands here.
final class CaptureOverlayView: NSView {
    weak var delegate: CaptureOverlayViewDelegate?

    private var layout: OverlayLayout?
    private let decorations = FrameDecorationsView()
    private let tab = GripTabView()
    private let label = SizeLabelView()
    private let positionBox = PositionBoxView()
    private let pinButton = TabButtonView(symbol: "pin", onSymbol: "pin.fill", label: "Pin", onLabel: "Unpin")
    /// Brings the Viewer forward, for when a click in the area sent another app's window over it.
    private let raiseButton = TabButtonView(
        symbol: "arrow.up.forward.app", onSymbol: "arrow.up.forward.app", label: "Show Viewer", onLabel: "Show Viewer")
    /// Picks a window for the area to take.
    private let pickButton = TabButtonView(
        symbol: "macwindow", onSymbol: "macwindow", label: "Fit Area to Window", onLabel: "Fit Area to Window")
    private var isDragging = false
    private var isRevealed = false

    /// Pinned: no band or handles, and the tab's pin is filled.
    var isPinned = false {
        didSet {
            pinButton.isOn = isPinned
            decorations.alphaValue = decorationsAlpha
        }
    }

    var style: FrameStyle {
        didSet {
            decorations.style = style
            tab.style = style
            pinButton.style = style
            raiseButton.style = style
            pickButton.style = style
            label.alphaValue = labelAlpha
            needsDisplay = true
        }
    }

    init(style: FrameStyle) {
        self.style = style
        decorations.style = style
        tab.style = style
        pinButton.style = style
        raiseButton.style = style
        pickButton.style = style
        super.init(frame: .zero)
        wantsLayer = true
        autoresizingMask = [.width, .height]
        for subview in [decorations, label, positionBox, tab, pinButton, raiseButton, pickButton] as [NSView] {
            addSubview(subview)
        }
        decorations.alphaValue = 0
        tab.alphaValue = 0
        positionBox.alphaValue = 0
        pinButton.alphaValue = 0
        raiseButton.alphaValue = 0
        pickButton.alphaValue = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: State

    /// Lays the frame out. Call after the window has taken `layout.windowFrame`.
    func update(
        layout: OverlayLayout, tabText: String, labelText: String, positionLines: [(key: String, value: String)]
    ) {
        let placementChanged = self.layout.map { $0.tabPlacement != layout.tabPlacement } ?? false
        self.layout = layout

        decorations.frame = bounds
        decorations.captureRect = local(layout.captureRect)
        decorations.handleRects = OverlayHandle.allCases.map {
            local(layout.handleRect($0, size: OverlayMetrics.standard.handleSize))
        }
        label.text = labelText
        label.frame = local(layout.labelRect)
        positionBox.lines = positionLines
        positionBox.frame = local(layout.positionRect)
        pinButton.frame = local(layout.pinRect)
        raiseButton.frame = local(layout.raiseRect)
        pickButton.frame = local(layout.pickRect)
        tab.text = tabText
        tab.showsShadow = layout.tabPlacement == .inside

        let tabFrame = local(layout.tabRect)
        if placementChanged {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = OverlayStyle.placementDuration
                context.allowsImplicitAnimation = true
                tab.animator().frame = tabFrame
            }
        } else {
            tab.frame = tabFrame
        }
        needsDisplay = true
    }

    /// Shows the band, handles and tab (hover), or the muted size label (rest).
    func setRevealed(_ revealed: Bool) {
        isRevealed = revealed
        NSAnimationContext.runAnimationGroup { context in
            context.duration = OverlayStyle.revealDuration
            decorations.animator().alphaValue = decorationsAlpha
            tab.animator().alphaValue = revealed ? 1 : 0
            positionBox.animator().alphaValue = revealed ? 1 : 0
            pinButton.animator().alphaValue = revealed ? 1 : 0
            raiseButton.animator().alphaValue = revealed ? 1 : 0
            pickButton.animator().alphaValue = revealed ? 1 : 0
            label.animator().alphaValue = labelAlpha
        }
    }

    private var labelAlpha: CGFloat { !isRevealed && style.showsLabelAtRest ? 1 : 0 }
    private var decorationsAlpha: CGFloat { isRevealed && !isPinned ? 1 : 0 }

    private func local(_ rect: CGRect) -> CGRect {
        guard let origin = layout?.windowFrame.origin else { return rect }
        return rect.offsetBy(dx: -origin.x, dy: -origin.y)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let layout else { return }
        let rect = local(layout.captureRect)
        let width = style.lineWidth
        // The line sits just outside the captured rect, so every captured pixel stays visible.
        let halo = NSBezierPath(rect: rect.insetBy(dx: -width - 0.5, dy: -width - 0.5))
        halo.lineWidth = 1
        OverlayStyle.halo(for: effectiveAppearance).setStroke()
        halo.stroke()
        let line = NSBezierPath(rect: rect.insetBy(dx: -width / 2, dy: -width / 2))
        line.lineWidth = width
        style.accent.setStroke()
        line.stroke()
    }

    // MARK: Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
                owner: self
            )
        )
    }

    override func mouseMoved(with event: NSEvent) { updateCursor() }
    override func cursorUpdate(with event: NSEvent) { updateCursor() }

    override func mouseExited(with event: NSEvent) {
        if !isDragging { NSCursor.arrow.set() }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        isDragging = true
        let point = NSEvent.mouseLocation
        let target = delegate?.overlayView(self, hitTargetAt: point)
        if target == .move || (target == nil && !isPinned) {
            NSCursor.closedHand.set()
        }
        delegate?.overlayView(self, mouseDownAt: point)
    }

    override func mouseDragged(with event: NSEvent) {
        delegate?.overlayView(self, mouseDraggedTo: NSEvent.mouseLocation)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        delegate?.overlayViewMouseUp(self)
        updateCursor()
    }

    private func updateCursor() {
        guard !isDragging else { return }
        OverlayStyle.cursor(for: delegate?.overlayView(self, hitTargetAt: NSEvent.mouseLocation)).set()
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        if delegate?.overlayView(self, keyDown: event) != true {
            super.keyDown(with: event)
        }
    }
}

/// The band outside the line and the eight resize handles.
private final class FrameDecorationsView: NSView {
    var captureRect: CGRect = .zero { didSet { needsDisplay = true } }
    var handleRects: [CGRect] = [] { didSet { needsDisplay = true } }
    var style: FrameStyle? { didSet { needsDisplay = true } }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let style else { return }
        let metrics = style.metrics
        let outer = metrics.lineWidth + metrics.bandWidth
        let band = NSBezierPath(rect: captureRect.insetBy(dx: -outer, dy: -outer))
        band.append(NSBezierPath(rect: captureRect.insetBy(dx: -style.lineWidth, dy: -style.lineWidth)))
        band.windingRule = .evenOdd
        style.band.setFill()
        band.fill()

        for rect in handleRects {
            style.handleFill.setFill()
            rect.fill()
            let outline = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            outline.lineWidth = 1
            style.accent.setStroke()
            outline.stroke()
        }
    }
}

/// The pill above the frame: a grip and the size in points and pixels. Dragging it moves the frame.
private final class GripTabView: NSView {
    var text = "" { didSet { if text != oldValue { needsDisplay = true } } }
    var style: FrameStyle? { didSet { needsDisplay = true } }
    var showsShadow = false {
        didSet {
            layer?.shadowOpacity = showsShadow ? 0.45 : 0
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowRadius = 3
        layer?.shadowOffset = CGSize(width: 0, height: -1)
        layer?.shadowOpacity = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let style else { return }
        let radius = bounds.height / 2
        style.tabFill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()

        // Grip: two columns of three dots in an 8 × 12 box.
        style.onTab.setFill()
        let gripOrigin = CGPoint(x: OverlayStyle.tabLeading, y: (bounds.height - 12) / 2)
        for column in 0..<2 {
            for row in 0..<3 {
                let center = CGPoint(x: gripOrigin.x + 2 + CGFloat(column) * 4, y: gripOrigin.y + 2 + CGFloat(row) * 4)
                NSBezierPath(ovalIn: CGRect(x: center.x - 1.2, y: center.y - 1.2, width: 2.4, height: 2.4)).fill()
            }
        }

        let attributes: [NSAttributedString.Key: Any] = [.font: OverlayStyle.tabFont, .foregroundColor: style.onTab]
        let size = (text as NSString).size(withAttributes: attributes)
        let x = OverlayStyle.tabLeading + OverlayStyle.gripWidth + OverlayStyle.tabGap
        (text as NSString).draw(
            at: CGPoint(x: x, y: ((bounds.height - size.height) / 2).rounded()), withAttributes: attributes)
    }
}

/// A square button beside the tab — the pin, the raise and pick buttons: the tab's colour with an outlined
/// symbol, or the accent with the filled one while it is on.
private final class TabButtonView: NSView {
    var style: FrameStyle? { didSet { needsDisplay = true } }
    var isOn = false { didSet { needsDisplay = true } }
    private let symbol: String
    private let onSymbol: String
    private let label: String
    private let onLabel: String

    init(symbol: String, onSymbol: String, label: String, onLabel: String) {
        self.symbol = symbol
        self.onSymbol = onSymbol
        self.label = label
        self.onLabel = onLabel
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let style else { return }
        (isOn ? style.accent : style.tabFill).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        let tint = isOn ? (style.handleFill == .white ? NSColor.white : .black) : style.onTab
        let configuration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [tint]))
        guard
            let pin = NSImage(
                systemSymbolName: isOn ? onSymbol : symbol, accessibilityDescription: isOn ? onLabel : label)?
                .withSymbolConfiguration(configuration)
        else { return }
        pin.draw(
            in: CGRect(
                x: ((bounds.width - pin.size.width) / 2).rounded(),
                y: ((bounds.height - pin.size.height) / 2).rounded(),
                width: pin.size.width, height: pin.size.height))
    }
}

/// The L T R B box beside the frame: keys muted, values right-aligned.
private final class PositionBoxView: NSView {
    var lines: [(key: String, value: String)] = [] { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        OverlayStyle.labelFill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        let keyAttributes: [NSAttributedString.Key: Any] = [
            .font: OverlayStyle.labelFont, .foregroundColor: NSColor.white.withAlphaComponent(0.6),
        ]
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: OverlayStyle.labelFont, .foregroundColor: NSColor.white,
        ]
        let padding = OverlayStyle.positionPadding
        for (index, line) in lines.enumerated() {
            let y = padding.height + CGFloat(index) * OverlayStyle.positionLineHeight
            (line.key as NSString).draw(at: CGPoint(x: padding.width, y: y), withAttributes: keyAttributes)
            let width = (line.value as NSString).size(withAttributes: valueAttributes).width
            (line.value as NSString).draw(
                at: CGPoint(x: bounds.width - padding.width - width, y: y), withAttributes: valueAttributes)
        }
    }
}

/// The muted size shown at rest.
private final class SizeLabelView: NSView {
    var text = "" { didSet { if text != oldValue { needsDisplay = true } } }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        OverlayStyle.labelFill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: OverlayStyle.labelFont, .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(
            at: CGPoint(
                x: ((bounds.width - size.width) / 2).rounded(), y: ((bounds.height - size.height) / 2).rounded()),
            withAttributes: attributes
        )
    }
}
