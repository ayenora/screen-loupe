import AppKit

/// The Color Meter panel at the right of the Viewer (mockup variant C).
///
/// Top: the inspected pixel — a large swatch and its value in every format, each with a copy button.
/// Below: the pinned colours, the last 8, newest first, each copyable and removable. A click in the
/// Viewer pins a colour.
///
/// It fills the width it is given. `scale` multiplies every font, size and spacing, so the panel
/// grows with the side column without any drawing transform.
final class ColorMeterPanel: NSView {
    /// The column's width at scale 1.
    static let width: CGFloat = 250

    var scale: CGFloat = 1 {
        didSet {
            guard scale != oldValue else { return }
            build()
            shownPins = []
            refresh()
        }
    }

    /// Called with the text to copy and a short description for the confirmation.
    var onCopy: ((_ text: String, _ what: String) -> Void)?

    private let inspector: PixelInspector
    private let sourceLabel = NSTextField(labelWithString: "")
    private let swatch = SwatchView()
    private var valueFields: [Format: NSTextField] = [:]
    private var copyButtons: [Format: NSButton] = [:]
    private var pinsStack = NSStackView()
    private var content: NSView?
    private let pinsHint = NSTextField(wrappingLabelWithString: "Click a pixel in the Viewer to pin its color.")
    private let clearButton = NSButton(title: "Clear", target: nil, action: nil)

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
        content?.removeFromSuperview()
        let s = scale
        let small = NSFont.smallSystemFontSize * s
        let title = sectionTitle("Color Meter")
        sourceLabel.font = .systemFont(ofSize: small)
        sourceLabel.textColor = .secondaryLabelColor
        sourceLabel.lineBreakMode = .byTruncatingTail

        let swatch = self.swatch
        swatch.removeConstraints(swatch.constraints)
        swatch.translatesAutoresizingMaskIntoConstraints = false
        swatch.heightAnchor.constraint(equalToConstant: 56 * s).isActive = true

        var rows: [NSView] = []
        for format in Format.allCases {
            let key = NSTextField(labelWithString: format.title)
            key.font = .systemFont(ofSize: small)
            key.textColor = .secondaryLabelColor
            key.widthAnchor.constraint(equalToConstant: 48 * s).isActive = true
            let value = NSTextField(labelWithString: "—")
            value.font = .monospacedSystemFont(ofSize: small, weight: .regular)
            value.lineBreakMode = .byTruncatingMiddle
            value.isSelectable = true
            value.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let copy = iconButton("doc.on.doc", label: "Copy \(format.title)")
            copy.tag = Format.allCases.firstIndex(of: format) ?? 0
            copy.action = #selector(copyFormat(_:))
            let row = NSStackView(views: [key, value, copy])
            row.spacing = 6 * s
            row.setHuggingPriority(.defaultHigh, for: .vertical)
            valueFields[format] = value
            copyButtons[format] = copy
            rows.append(row)
        }

        let pinnedTitle = sectionTitle("Pinned")
        clearButton.bezelStyle = .inline
        clearButton.font = .systemFont(ofSize: small)
        clearButton.target = self
        clearButton.action = #selector(clearPins)
        let pinnedHeader = NSStackView(views: [pinnedTitle, NSView(), clearButton])

        pinsStack = NSStackView()
        pinsStack.orientation = .vertical
        pinsStack.alignment = .leading
        pinsStack.spacing = 4 * s
        pinsHint.font = .systemFont(ofSize: small)
        pinsHint.textColor = .tertiaryLabelColor

        let stack = NSStackView(
            views: [title, sourceLabel, swatch] + rows + [
                separator(), pinnedHeader, pinsStack, pinsHint,
            ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6 * s
        stack.setCustomSpacing(10 * s, after: swatch)
        stack.setCustomSpacing(12 * s, after: rows.last ?? swatch)
        stack.edgeInsets = NSEdgeInsets(top: 12 * s, left: 14 * s, bottom: 12 * s, right: 12 * s)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        content = stack
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])
        for view in [swatch] + rows + [pinnedHeader, pinsStack] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -26 * s).isActive = true
        }
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text.uppercased())
        label.font = .systemFont(ofSize: 10 * scale, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func separator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private func iconButton(_ symbol: String, label: String) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .inline
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12 * scale, weight: .regular))
        button.toolTip = label
        button.target = self
        return button
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
            valueFields[format]?.stringValue = text ?? "—"
            valueFields[format]?.toolTip = text
            copyButtons[format]?.isEnabled = text != nil
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

    private var shownPins: [PinnedColor] = []

    private func refreshPins() {
        let pins = inspector.pins
        clearButton.isHidden = pins.isEmpty
        pinsHint.isHidden = !pins.isEmpty
        guard pins != shownPins else { return }
        shownPins = pins
        pinsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, pin) in pins.enumerated() {
            let row = pinRow(pin, index: index)
            pinsStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: pinsStack.widthAnchor).isActive = true
        }
    }

    private func pinRow(_ pin: PinnedColor, index: Int) -> NSView {
        let swatch = SwatchView()
        swatch.color = NSColor(
            srgbRed: pin.sample.srgb.red, green: pin.sample.srgb.green, blue: pin.sample.srgb.blue, alpha: 1)
        swatch.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            swatch.widthAnchor.constraint(equalToConstant: 18 * scale),
            swatch.heightAnchor.constraint(equalToConstant: 18 * scale),
        ])
        let hex = NSTextField(labelWithString: pin.hex)
        hex.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize * scale, weight: .medium)
        hex.isSelectable = true
        let position = NSTextField(labelWithString: "\(pin.x), \(pin.y)")
        position.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize * scale, weight: .regular)
        position.textColor = .secondaryLabelColor
        let copy = iconButton("doc.on.doc", label: "Copy \(pin.hex)")
        copy.tag = index
        copy.action = #selector(copyPin(_:))
        let remove = iconButton("xmark", label: "Remove")
        remove.tag = index
        remove.action = #selector(removePin(_:))
        let row = NSStackView(views: [swatch, hex, position, NSView(), copy, remove])
        row.spacing = 6 * scale
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    // MARK: Actions

    @objc private func copyFormat(_ sender: NSButton) {
        let format = Format.allCases[sender.tag]
        guard let text = valueFields[format]?.toolTip else { return }
        onCopy?(text, text)
    }

    @objc private func copyPin(_ sender: NSButton) {
        guard inspector.pins.indices.contains(sender.tag) else { return }
        let hex = inspector.pins[sender.tag].hex
        onCopy?(hex, hex)
    }

    @objc private func removePin(_ sender: NSButton) {
        inspector.removePin(at: sender.tag)
    }

    @objc private func clearPins() {
        inspector.clearPins()
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
