import AppKit

/// The panels at the right of the Viewer, top down: the Color Meter, then References
/// (docs/product.md, References). With both open only one is expanded and fills the height; the
/// other is a strip in its place that expands it when clicked.
final class SidePanelStack: NSView {
    var onExpand: ((SidePanel) -> Void)?

    private let meter: NSView
    private let references: NSView
    private let meterStrip = PanelStrip(title: "Color Meter")
    private let referencesStrip = PanelStrip(title: "References")
    private static let stripHeight: CGFloat = 32

    init(meter: NSView, references: NSView) {
        self.meter = meter
        self.references = references
        super.init(frame: .zero)
        wantsLayer = true
        // Laid out by hand in `layout()`: in a stack view the SwiftUI list collapsed to nothing.
        for view in [meterStrip, meter, referencesStrip, references] {
            view.translatesAutoresizingMaskIntoConstraints = true
            addSubview(view)
        }
        widthAnchor.constraint(equalToConstant: ColorMeterPanel.width).isActive = true
        meterStrip.onClick = { [weak self] in self?.onExpand?(.colorMeter) }
        referencesStrip.onClick = { [weak self] in self?.onExpand?(.references) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

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

    override func layout() {
        super.layout()
        let strips = [meterStrip, referencesStrip].filter { !$0.isHidden }.count
        let panelHeight = max(0, bounds.height - CGFloat(strips) * Self.stripHeight)
        var y: CGFloat = 0
        for view in [meterStrip, meter, referencesStrip, references] where !view.isHidden {
            let height = view is PanelStrip ? Self.stripHeight : panelHeight
            view.frame = CGRect(x: 0, y: y, width: bounds.width, height: height)
            y += height
        }
    }
}

/// A collapsed panel: its title and a chevron. Clicking expands it.
private final class PanelStrip: NSView {
    var onClick: (() -> Void)?

    init(title: String) {
        super.init(frame: .zero)
        wantsLayer = true
        let label = NSTextField(labelWithString: title)
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
