import AppKit

/// The Color Meter panel at the right of the Viewer (mockup variant C).
///
/// Top: the inspected pixel — a large swatch and its value in every format, each with a copy button.
/// Below: the pinned colours, the last 8, newest first, each copyable and removable. A click in the
/// Viewer pins a colour.
///
/// It fills the width it is given. `scale` multiplies every font, size and spacing, so the panel
/// grows with the side column without any drawing transform. The views are built once; a new scale
/// only changes their fonts and constants, so dragging the column's edge stays cheap.
final class ColorMeterPanel: NSView {
    var scale: CGFloat = 1 {
        didSet { if scale != oldValue { applyScale() } }
    }

    /// Called with the text to copy and a short description for the confirmation.
    var onCopy: ((_ text: String, _ what: String) -> Void)?

    private let inspector: PixelInspector
    private let title = ColorMeterPanel.sectionTitle("Color Meter")
    private let sourceLabel = NSTextField(labelWithString: "")
    private let swatch = SwatchView()
    private lazy var swatchHeight = swatch.heightAnchor.constraint(equalToConstant: 0)
    private var rows: [Format: FormatRow] = [:]
    /// The text each format shows now, for its copy button; `nil` when there is none.
    private var values: [Format: String] = [:]
    private let pinnedTitle = ColorMeterPanel.sectionTitle("Pinned")
    private let pinnedHeader = NSStackView()
    private let pinsStack = NSStackView()
    private let pinsHint = NSTextField(wrappingLabelWithString: "Click a pixel in the Viewer to pin its color.")
    private let clearButton = NSButton(title: "Clear", target: nil, action: nil)
    private let stack = NSStackView()
    /// The rows that span the stack's width minus its insets.
    private var insetWidths: [NSLayoutConstraint] = []
    private var shownPins: [PinnedColor] = []

    private enum Format: CaseIterable {
        case hex, css, swiftUI, appKit, native, position

        var title: String {
            switch self {
            case .hex: "HEX"
            case .css: "CSS"
            case .swiftUI: "SwiftUI"
            case .appKit: "AppKit"
            case .native: "Native"
            case .position: "X, Y"
            }
        }
    }

    init(inspector: PixelInspector) {
        self.inspector = inspector
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(divider)
        build()
        applyScale()
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // The background and the left hairline are layer properties, not drawn in `draw(_:)`: a panel
    // that draws itself made AppKit composite the Viewer's Metal layer away, leaving it white.
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        divider.backgroundColor = NSColor.separatorColor.cgColor
    }

    private let divider = CALayer()

    override func layout() {
        super.layout()
        divider.frame = CGRect(x: 0, y: 0, width: 1, height: bounds.height)
    }

    // MARK: Layout

    private func build() {
        sourceLabel.textColor = .secondaryLabelColor
        sourceLabel.lineBreakMode = .byTruncatingTail
        swatch.translatesAutoresizingMaskIntoConstraints = false
        swatchHeight.isActive = true

        var formatRows: [NSView] = []
        for format in Format.allCases {
            let row = FormatRow(title: format.title, target: self, action: #selector(copyFormat(_:)))
            row.copy.tag = Format.allCases.firstIndex(of: format) ?? 0
            rows[format] = row
            formatRows.append(row)
        }

        clearButton.bezelStyle = .inline
        clearButton.target = self
        clearButton.action = #selector(clearPins)
        for view in [pinnedTitle, NSView(), clearButton] { pinnedHeader.addArrangedSubview(view) }

        pinsStack.orientation = .vertical
        pinsStack.alignment = .leading
        pinsHint.textColor = .tertiaryLabelColor

        for view in [title, sourceLabel, swatch] + formatRows + [separator(), pinnedHeader, pinsStack, pinsHint] {
            stack.addArrangedSubview(view)
        }
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])
        insetWidths = ([swatch] + formatRows + [pinnedHeader, pinsStack]).map {
            $0.widthAnchor.constraint(equalTo: stack.widthAnchor)
        }
        NSLayoutConstraint.activate(insetWidths)
    }

    /// Sets every font, size and spacing for `scale`.
    private func applyScale() {
        let s = scale
        let small = NSFont.smallSystemFontSize * s
        for label in [title, pinnedTitle] {
            label.font = .systemFont(ofSize: 10 * s, weight: .semibold)
        }
        sourceLabel.font = .systemFont(ofSize: small)
        swatchHeight.constant = 56 * s
        for row in rows.values { row.apply(scale: s) }
        clearButton.font = .systemFont(ofSize: small)
        pinsStack.spacing = 4 * s
        pinsHint.font = .systemFont(ofSize: small)
        for row in pinsStack.arrangedSubviews.compactMap({ $0 as? PinRow }) { row.apply(scale: s) }

        stack.spacing = 6 * s
        stack.setCustomSpacing(10 * s, after: swatch)
        if let last = rows[Format.allCases.last!] { stack.setCustomSpacing(12 * s, after: last) }
        stack.edgeInsets = NSEdgeInsets(top: 12 * s, left: 14 * s, bottom: 12 * s, right: 12 * s)
        for constraint in insetWidths { constraint.constant = -26 * s }
    }

    private static func sectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text.uppercased())
        label.textColor = .secondaryLabelColor
        return label
    }

    private func separator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    // MARK: Content

    /// Reflects the inspector: the inspected pixel and the pins.
    func refresh() {
        let probe = inspector.probe
        switch probe?.source {
        case .viewer?: sourceLabel.stringValue = "Under the mouse in the Viewer"
        case .captureArea?: sourceLabel.stringValue = "Under the cursor in the Capture Area"
        case nil: sourceLabel.stringValue = "Point at a pixel"
        }
        let sample = probe?.sample
        swatch.color = sample.map { NSColor(srgbRed: $0.srgb.red, green: $0.srgb.green, blue: $0.srgb.blue, alpha: 1) }
        for format in Format.allCases {
            let text = probe.flatMap { value(format, sample: sample, probe: $0) }
            values[format] = text
            rows[format]?.show(text)
        }
        refreshPins()
    }

    private func value(_ format: Format, sample: ColorSample?, probe: PixelInspector.Probe) -> String? {
        if format == .position { return "\(probe.x), \(probe.y)" }
        guard let sample else { return nil }
        switch format {
        case .hex: return sample.hex
        case .css: return sample.cssRGB
        case .swiftUI: return sample.swiftUI
        case .appKit: return sample.appKit
        case .native: return "\(sample.nativeValues)  \(sample.nativeSpaceName)"
        case .position: return nil
        }
    }

    private func refreshPins() {
        let pins = inspector.pins
        clearButton.isHidden = pins.isEmpty
        pinsHint.isHidden = !pins.isEmpty
        guard pins != shownPins else { return }
        shownPins = pins
        pinsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, pin) in pins.enumerated() {
            let row = PinRow(pin, index: index, target: self)
            row.apply(scale: scale)
            pinsStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: pinsStack.widthAnchor).isActive = true
        }
    }

    // MARK: Actions

    @objc fileprivate func copyFormat(_ sender: NSButton) {
        guard let text = values[Format.allCases[sender.tag]] else { return }
        onCopy?(text, text)
    }

    @objc fileprivate func copyPin(_ sender: NSButton) {
        guard inspector.pins.indices.contains(sender.tag) else { return }
        let hex = inspector.pins[sender.tag].hex
        onCopy?(hex, hex)
    }

    @objc fileprivate func removePin(_ sender: NSButton) {
        inspector.removePin(at: sender.tag)
    }

    @objc private func clearPins() {
        inspector.clearPins()
    }
}

/// A borderless icon button whose symbol is redrawn at each scale.
private final class IconButton: NSButton {
    private let symbol: String
    private let label: String

    init(_ symbol: String, label: String, target: AnyObject, action: Selector) {
        self.symbol = symbol
        self.label = label
        super.init(frame: .zero)
        bezelStyle = .inline
        isBordered = false
        toolTip = label
        self.target = target
        self.action = action
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func apply(scale: CGFloat) {
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12 * scale, weight: .regular))
    }
}

/// One format of the inspected pixel: its name, its value and a copy button.
private final class FormatRow: NSStackView {
    let copy: IconButton
    private let key: NSTextField
    private let value = NSTextField(labelWithString: "—")
    private lazy var keyWidth = key.widthAnchor.constraint(equalToConstant: 0)

    init(title: String, target: AnyObject, action: Selector) {
        key = NSTextField(labelWithString: title)
        copy = IconButton("doc.on.doc", label: "Copy \(title)", target: target, action: action)
        super.init(frame: .zero)
        key.textColor = .secondaryLabelColor
        keyWidth.isActive = true
        value.lineBreakMode = .byTruncatingMiddle
        value.isSelectable = true
        value.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for view in [key, value, copy] { addArrangedSubview(view) }
        setHuggingPriority(.defaultHigh, for: .vertical)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func apply(scale s: CGFloat) {
        let small = NSFont.smallSystemFontSize * s
        key.font = .systemFont(ofSize: small)
        keyWidth.constant = 48 * s
        value.font = .monospacedSystemFont(ofSize: small, weight: .regular)
        copy.apply(scale: s)
        spacing = 6 * s
    }

    /// `nil`: nothing to show or copy.
    func show(_ text: String?) {
        value.stringValue = text ?? "—"
        value.toolTip = text
        copy.isEnabled = text != nil
    }
}

/// One pinned colour: swatch, HEX, where it was picked, copy and remove.
private final class PinRow: NSStackView {
    private let swatch = SwatchView()
    private let hex: NSTextField
    private let position: NSTextField
    private let copy: IconButton
    private let remove: IconButton
    private lazy var swatchSize = [
        swatch.widthAnchor.constraint(equalToConstant: 0), swatch.heightAnchor.constraint(equalToConstant: 0),
    ]

    init(_ pin: PinnedColor, index: Int, target: ColorMeterPanel) {
        hex = NSTextField(labelWithString: pin.hex)
        position = NSTextField(labelWithString: "\(pin.x), \(pin.y)")
        copy = IconButton(
            "doc.on.doc", label: "Copy \(pin.hex)", target: target, action: #selector(ColorMeterPanel.copyPin(_:)))
        remove = IconButton("xmark", label: "Remove", target: target, action: #selector(ColorMeterPanel.removePin(_:)))
        super.init(frame: .zero)
        swatch.color = NSColor(
            srgbRed: pin.sample.srgb.red, green: pin.sample.srgb.green, blue: pin.sample.srgb.blue, alpha: 1)
        swatch.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate(swatchSize)
        hex.isSelectable = true
        position.textColor = .secondaryLabelColor
        copy.tag = index
        remove.tag = index
        for view in [swatch, hex, position, NSView(), copy, remove] { addArrangedSubview(view) }
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func apply(scale s: CGFloat) {
        for constraint in swatchSize { constraint.constant = 18 * s }
        hex.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize * s, weight: .medium)
        position.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize * s, weight: .regular)
        copy.apply(scale: s)
        remove.apply(scale: s)
        spacing = 6 * s
    }
}

/// A colour swatch with a hairline border, so white and near-background colours stay visible.
final class SwatchView: NSView {
    var color: NSColor? { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
        (color ?? NSColor.quaternaryLabelColor).setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}
