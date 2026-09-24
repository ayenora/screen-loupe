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
/// The line is always drawn. The band, the handles and the tab fade in on hover; the muted size
/// label shows at rest. Subviews never take the mouse, so every event lands here.
final class CaptureOverlayView: NSView {
    weak var delegate: CaptureOverlayViewDelegate?

    private var layout: OverlayLayout?
    private let decorations = FrameDecorationsView()
    private let tab = GripTabView()
    private let label = SizeLabelView()
    private var isDragging = false

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        autoresizingMask = [.width, .height]
        for subview in [decorations, label, tab] as [NSView] {
            addSubview(subview)
        }
        decorations.alphaValue = 0
        tab.alphaValue = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: State

    /// Lays the frame out. Call after the window has taken `layout.windowFrame`.
    func update(layout: OverlayLayout, tabText: String, labelText: String) {
        let placementChanged = self.layout.map { $0.tabPlacement != layout.tabPlacement } ?? false
        self.layout = layout

        decorations.frame = bounds
        decorations.captureRect = local(layout.captureRect)
        decorations.handleRects = OverlayHandle.allCases.map {
            local(layout.handleRect($0, size: OverlayMetrics.standard.handleSize))
        }
        label.text = labelText
        label.frame = local(layout.labelRect)
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
        NSAnimationContext.runAnimationGroup { context in
            context.duration = OverlayStyle.revealDuration
            decorations.animator().alphaValue = revealed ? 1 : 0
            tab.animator().alphaValue = revealed ? 1 : 0
            label.animator().alphaValue = revealed ? 0 : 1
        }
    }

    private func local(_ rect: CGRect) -> CGRect {
        guard let origin = layout?.windowFrame.origin else { return rect }
        return rect.offsetBy(dx: -origin.x, dy: -origin.y)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let layout else { return }
        let rect = local(layout.captureRect)
        // The line sits just outside the captured rect, so every captured pixel stays visible.
        let halo = NSBezierPath(rect: rect.insetBy(dx: -1.5, dy: -1.5))
        halo.lineWidth = 1
        OverlayStyle.halo(for: effectiveAppearance).setStroke()
        halo.stroke()
        let line = NSBezierPath(rect: rect.insetBy(dx: -0.5, dy: -0.5))
        line.lineWidth = 1
        OverlayStyle.accent.setStroke()
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
        if delegate?.overlayView(self, hitTargetAt: point) ?? .move == .move {
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

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let metrics = OverlayMetrics.standard
        let outer = metrics.lineWidth + metrics.bandWidth
        let band = NSBezierPath(rect: captureRect.insetBy(dx: -outer, dy: -outer))
        band.append(NSBezierPath(rect: captureRect.insetBy(dx: -metrics.lineWidth, dy: -metrics.lineWidth)))
        band.windingRule = .evenOdd
        OverlayStyle.band.setFill()
        band.fill()

        for rect in handleRects {
            NSColor.white.setFill()
            rect.fill()
            let outline = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            outline.lineWidth = 1
            OverlayStyle.accent.setStroke()
            outline.stroke()
        }
    }
}

/// The pill above the frame: a grip and the size in points and pixels. Dragging it moves the frame.
private final class GripTabView: NSView {
    var text = "" { didSet { if text != oldValue { needsDisplay = true } } }
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
        let radius = bounds.height / 2
        OverlayStyle.tabFill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()

        // Grip: two columns of three dots in an 8 × 12 box.
        NSColor.white.setFill()
        let gripOrigin = CGPoint(x: OverlayStyle.tabLeading, y: (bounds.height - 12) / 2)
        for column in 0..<2 {
            for row in 0..<3 {
                let center = CGPoint(x: gripOrigin.x + 2 + CGFloat(column) * 4, y: gripOrigin.y + 2 + CGFloat(row) * 4)
                NSBezierPath(ovalIn: CGRect(x: center.x - 1.2, y: center.y - 1.2, width: 2.4, height: 2.4)).fill()
            }
        }

        let attributes: [NSAttributedString.Key: Any] = [.font: OverlayStyle.tabFont, .foregroundColor: NSColor.white]
        let size = (text as NSString).size(withAttributes: attributes)
        let x = OverlayStyle.tabLeading + OverlayStyle.gripWidth + OverlayStyle.tabGap
        (text as NSString).draw(
            at: CGPoint(x: x, y: ((bounds.height - size.height) / 2).rounded()), withAttributes: attributes)
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
