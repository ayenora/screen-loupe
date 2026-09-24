import AppKit

/// The panels at the right of the Viewer, top down: the Color Meter, then References
/// (docs/product.md, References). With both open only one is expanded and fills the height; the
/// other is a strip in its place that expands it when clicked.
///
/// Dragging the left edge widens the column within `SidePanel.widthRange`, and everything in it grows
/// in proportion: each panel multiplies its own fonts, sizes and spacings by `scale`. No drawing
/// transform is involved, so clicks land where things are drawn. The Color Meter scrolls when the
/// column is short.
final class SidePanelStack: NSView {
    var onExpand: ((SidePanel) -> Void)?
    /// Called with the new width when a drag of the left edge ends.
    var onResize: ((CGFloat) -> Void)?
    /// Called with the content scale, 1 at the narrowest, whenever the width changes.
    var onScale: ((CGFloat) -> Void)?

    /// How far into the column the left edge can be grabbed, in points.
    private static let edgeGrab: CGFloat = 5
    private static let stripHeight: CGFloat = 32

    private let meterPanel: ColorMeterPanel
    private let meter = NSScrollView()
    private let references: NSView
    private let meterStrip = PanelStrip(title: "Color Meter")
    private let referencesStrip = PanelStrip(title: "References")
    private var widthConstraint: NSLayoutConstraint!
    private var resizeStart: (mouseX: CGFloat, width: CGFloat)?

    init(meter panel: ColorMeterPanel, references: NSView) {
        meterPanel = panel
        self.references = references
        super.init(frame: .zero)
        wantsLayer = true
        setUpScrolling()
        // Laid out by hand in `layout()`: in a stack view the SwiftUI list collapsed to nothing.
        for view in [meterStrip, meter, referencesStrip, references] {
            view.translatesAutoresizingMaskIntoConstraints = true
            addSubview(view)
        }
        widthConstraint = widthAnchor.constraint(equalToConstant: SidePanel.widthRange.lowerBound)
        widthConstraint.isActive = true
        meterStrip.onClick = { [weak self] in self?.onExpand?(.colorMeter) }
        referencesStrip.onClick = { [weak self] in self?.onExpand?(.references) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The Color Meter as the scroll view's document: full width, as tall as its content and at
    /// least as tall as the view, from the top.
    private func setUpScrolling() {
        meter.contentView = FlippedClipView()
        meter.hasVerticalScroller = true
        meter.autohidesScrollers = true
        meter.drawsBackground = false
        meter.documentView = meterPanel
        meterPanel.translatesAutoresizingMaskIntoConstraints = false
        let clip = meter.contentView
        let hug = meterPanel.heightAnchor.constraint(equalToConstant: 0)
        hug.priority = .defaultLow
        NSLayoutConstraint.activate([
            meterPanel.topAnchor.constraint(equalTo: clip.topAnchor),
            meterPanel.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            meterPanel.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            meterPanel.heightAnchor.constraint(greaterThanOrEqualTo: clip.heightAnchor),
            hug,
        ])
    }

    override var isFlipped: Bool { true }

    // Behind the References panel, which doesn't paint its own; layer properties, not `draw(_:)`,
    // like the Color Meter (see its note on the Metal layer).
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 0.5
    }

    /// Which panels are open, and which of two is expanded.
    func show(meter showsMeter: Bool, references showsReferences: Bool, expanded: SidePanel) {
        let both = showsMeter && showsReferences
        meter.isHidden = !showsMeter || (both && expanded != .colorMeter)
        meterStrip.isHidden = !(both && expanded != .colorMeter)
        references.isHidden = !showsReferences || (both && expanded != .references)
        referencesStrip.isHidden = !(both && expanded != .references)
        isHidden = !showsMeter && !showsReferences
        needsLayout = true
    }

    // MARK: Width and scale

    var width: CGFloat {
        get { widthConstraint.constant }
        set {
            widthConstraint.constant = min(
                max(newValue, SidePanel.widthRange.lowerBound), SidePanel.widthRange.upperBound)
            let scale = self.scale
            meterPanel.scale = scale
            meterStrip.scale = scale
            referencesStrip.scale = scale
            onScale?(scale)
            needsLayout = true
        }
    }

    var scale: CGFloat { width / SidePanel.widthRange.lowerBound }

    override func layout() {
        super.layout()
        let strip = Self.stripHeight * scale
        let strips = [meterStrip, referencesStrip].filter { !$0.isHidden }.count
        let panelHeight = max(0, bounds.height - CGFloat(strips) * strip)
        var y: CGFloat = 0
        for view in [meterStrip, meter, referencesStrip, references] where !view.isHidden {
            let height = view is PanelStrip ? strip : panelHeight
            view.frame = CGRect(x: 0, y: y, width: bounds.width, height: height)
            y += height
        }
        window?.invalidateCursorRects(for: self)
    }

    private var edgeRect: CGRect {
        CGRect(x: 0, y: 0, width: Self.edgeGrab, height: bounds.height)
    }

    override func resetCursorRects() {
        addCursorRect(edgeRect, cursor: .resizeLeftRight)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden else { return nil }
        return edgeRect.contains(convert(point, from: superview)) ? self : super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        resizeStart = (event.locationInWindow.x, width)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = resizeStart else { return }
        // Dragging left widens the column.
        width = start.width + start.mouseX - event.locationInWindow.x
    }

    override func mouseUp(with event: NSEvent) {
        guard resizeStart != nil else { return }
        resizeStart = nil
        onResize?(width)
    }
}

/// Scrolls from the top, not from the bottom as AppKit's default does.
private final class FlippedClipView: NSClipView {
    override var isFlipped: Bool { true }
}

/// A collapsed panel: its title and a chevron. Clicking expands it.
private final class PanelStrip: NSView {
    var onClick: (() -> Void)?
    var scale: CGFloat = 1 {
        didSet { label.font = .systemFont(ofSize: NSFont.systemFontSize * scale, weight: .semibold) }
    }
    private let label: NSTextField

    init(title: String) {
        label = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        wantsLayer = true
        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        let chevron = NSImageView(
            image: NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Expand") ?? NSImage())
        chevron.contentTintColor = .secondaryLabelColor
        for view in [label, chevron] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityRole(.button)
        setAccessibilityLabel("Expand \(title)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // Layer properties, not `draw(_:)`, like the Color Meter: see its note on the Metal layer.
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 0.5
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }
}
