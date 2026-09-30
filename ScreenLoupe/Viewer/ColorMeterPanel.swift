import AppKit

/// The Color Meter panel at the right of the Viewer.
///
/// Top down: the colour in focus — the live pixel, or a kept colour clicked below — as a large
/// swatch and its value in every format, each with a copy button; Contrast, Text on Background with
/// the WCAG ratio and verdicts; eight Favorites; Recent, the last 8 colours clicked in the Viewer.
/// Where each click sends a colour is `ColorMeterState`'s.
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
    /// Called with a short confirmation, such as "Favorites are full".
    var onFeedback: ((String) -> Void)?
    /// Whether a click on the image picks a colour. Then, while the pointer is over the image, the
    /// slot the click would fill shows the pixel under it.
    var isPicking = false {
        didSet { if isPicking != oldValue { refresh() } }
    }

    private let inspector: PixelInspector
    private let title = ColorMeterPanel.sectionTitle("Color Meter")
    private let focusHeader = NSStackView()
    private let focusLabel = NSTextField(labelWithString: "")
    /// The position, or which slot: kept whole while `focusLabel` truncates.
    private let focusDetail = NSTextField(labelWithString: "")
    private let swatch = SwatchView()
    private lazy var swatchHeight = swatch.heightAnchor.constraint(equalToConstant: 0)
    private var rows: [Format: FormatRow] = [:]
    /// The text each format shows now, for its copy button; `nil` when there is none.
    private var values: [Format: String] = [:]

    private let contrastHeader = NSStackView()
    private let contrastTitle = ColorMeterPanel.sectionTitle("Contrast")
    private let swapButton = NSButton(title: "Swap", target: nil, action: nil)
    private let slotsRow = NSStackView()
    private let slotButtons = ColorMeterState.Slot.allCases.map { ContrastSlotButton(slot: $0) }
    private let previewRow = NSStackView()
    private let preview = ContrastPreview()
    private lazy var previewSize = [
        preview.widthAnchor.constraint(equalToConstant: 0), preview.heightAnchor.constraint(equalToConstant: 0),
    ]
    private let ratioLabel = NSTextField(labelWithString: "—")
    private let verdictLabels = ColorContrast.Level.allCases.map { _ in NSTextField(labelWithString: "") }
    private lazy var verdictGrid = NSGridView(views: [
        [verdictLabels[0], verdictLabels[1]], [verdictLabels[2], verdictLabels[3]],
    ])
    private let largeNote = NSTextField(wrappingLabelWithString: "Large = 18 pt, or 14 pt bold.")
    private let hintLabel = NSTextField(wrappingLabelWithString: "")
    /// Two lines, whichever hint shows, so the panel doesn't move when the target changes.
    private lazy var hintHeight = hintLabel.heightAnchor.constraint(equalToConstant: 0)

    private let favoritesTitle = ColorMeterPanel.sectionTitle("Favorites")
    private let favoritesRow = NSStackView()
    private let favoriteButtons = (0..<ColorMeterState.favoriteCount).map { FavoriteButton(index: $0) }

    private let recentTitle = ColorMeterPanel.sectionTitle("Recent")
    private let recentHeader = NSStackView()
    private let recentStack = NSStackView()
    private let recentHint = NSTextField(wrappingLabelWithString: "Click a pixel in the Viewer to keep its color.")
    private let clearButton = NSButton(title: "Clear", target: nil, action: nil)
    private let stack = NSStackView()
    /// The rows that span the stack's width minus its insets.
    private var insetWidths: [NSLayoutConstraint] = []
    private var shownRecent: [PickedColor] = []
    /// The favourites the menus were made for.
    private var shownFavorites: [PickedColor?] = []

    private enum Format: CaseIterable {
        case hex, css, swiftUI, appKit, native

        var title: String {
            switch self {
            case .hex: "HEX"
            case .css: "CSS"
            case .swiftUI: "SwiftUI"
            case .appKit: "AppKit"
            case .native: "Native"
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
        focusLabel.textColor = .secondaryLabelColor
        focusLabel.lineBreakMode = .byTruncatingTail
        focusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        focusDetail.textColor = .secondaryLabelColor
        for button in [swapButton, clearButton] { button.bezelStyle = .inline }
        // One line of labels, never hidden, so the row keeps its height whatever is in focus.
        for view in [focusLabel, focusDetail, NSView()] { focusHeader.addArrangedSubview(view) }
        swatch.translatesAutoresizingMaskIntoConstraints = false
        swatchHeight.isActive = true

        var formatRows: [NSView] = []
        for format in Format.allCases {
            let row = FormatRow(title: format.title, target: self, action: #selector(copyFormat(_:)))
            row.copy.tag = Format.allCases.firstIndex(of: format) ?? 0
            rows[format] = row
            formatRows.append(row)
        }

        swapButton.target = self
        swapButton.action = #selector(swapContrast)
        swapButton.setAccessibilityLabel("Swap Text and Background")
        for view in [contrastTitle, NSView(), swapButton] { contrastHeader.addArrangedSubview(view) }
        slotsRow.distribution = .fillEqually
        for button in slotButtons {
            button.target = self
            button.action = #selector(clickContrastSlot(_:))
            slotsRow.addArrangedSubview(button)
        }
        preview.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate(previewSize)
        for view in [preview, ratioLabel, NSView()] { previewRow.addArrangedSubview(view) }
        verdictGrid.rowAlignment = .firstBaseline
        for label in [largeNote, hintLabel] { label.textColor = .secondaryLabelColor }
        hintLabel.maximumNumberOfLines = 2
        hintHeight.isActive = true

        favoritesRow.distribution = .fillEqually
        for button in favoriteButtons {
            button.target = self
            button.action = #selector(clickFavorite(_:))
            favoritesRow.addArrangedSubview(button)
            button.heightAnchor.constraint(equalTo: button.widthAnchor).isActive = true
        }

        clearButton.target = self
        clearButton.action = #selector(clearRecent)
        for view in [recentTitle, NSView(), clearButton] { recentHeader.addArrangedSubview(view) }
        recentStack.orientation = .vertical
        recentStack.alignment = .leading
        recentHint.textColor = .tertiaryLabelColor

        let contrast: [NSView] = [contrastHeader, slotsRow, previewRow, verdictGrid, largeNote, hintLabel]
        let top: [NSView] = [title, focusHeader, swatch] + formatRows
        for view in top + [separator()] + contrast + [separator(), favoritesTitle, favoritesRow, separator()]
            + [recentHeader, recentStack, recentHint]
        {
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
        let fullWidth: [NSView] =
            [focusHeader, swatch] + formatRows + [contrastHeader, slotsRow, previewRow, largeNote, hintLabel]
            + [favoritesRow, recentHeader, recentStack, recentHint]
        insetWidths = fullWidth.map { $0.widthAnchor.constraint(equalTo: stack.widthAnchor) }
        NSLayoutConstraint.activate(insetWidths)
    }

    /// Sets every font, size and spacing for `scale`.
    private func applyScale() {
        let s = scale
        let small = NSFont.smallSystemFontSize * s
        for label in [title, contrastTitle, favoritesTitle, recentTitle] {
            label.font = .systemFont(ofSize: 10 * s, weight: .semibold)
        }
        focusLabel.font = .systemFont(ofSize: small)
        focusDetail.font = .monospacedDigitSystemFont(ofSize: small, weight: .regular)
        focusHeader.spacing = 4 * s
        for button in [swapButton, clearButton] { button.font = .systemFont(ofSize: small) }
        swatchHeight.constant = 56 * s
        for row in rows.values { row.apply(scale: s) }

        slotsRow.spacing = 8 * s
        for button in slotButtons { button.apply(scale: s) }
        for constraint in previewSize { constraint.constant = 44 * s }
        previewSize[0].constant = 64 * s
        preview.scale = s
        previewRow.spacing = 10 * s
        ratioLabel.font = .monospacedDigitSystemFont(ofSize: 20 * s, weight: .semibold)
        verdictGrid.columnSpacing = 12 * s
        verdictGrid.rowSpacing = 3 * s
        for label in [largeNote, hintLabel] { label.font = .systemFont(ofSize: small) }
        let twoLines = NSTextField(wrappingLabelWithString: "A\nA")
        twoLines.font = hintLabel.font
        hintHeight.constant = twoLines.intrinsicContentSize.height

        favoritesRow.spacing = 4 * s
        for button in favoriteButtons { button.scale = s }

        recentStack.spacing = 4 * s
        recentHint.font = .systemFont(ofSize: small)
        for row in recentStack.arrangedSubviews.compactMap({ $0 as? RecentRow }) { row.apply(scale: s) }

        stack.spacing = 6 * s
        stack.setCustomSpacing(10 * s, after: swatch)
        if let last = rows[Format.allCases.last!] { stack.setCustomSpacing(12 * s, after: last) }
        stack.setCustomSpacing(10 * s, after: slotsRow)
        stack.setCustomSpacing(10 * s, after: previewRow)
        stack.setCustomSpacing(10 * s, after: verdictGrid)
        stack.setCustomSpacing(12 * s, after: hintLabel)
        stack.setCustomSpacing(12 * s, after: favoritesRow)
        stack.edgeInsets = NSEdgeInsets(top: 12 * s, left: 14 * s, bottom: 12 * s, right: 12 * s)
        for constraint in insetWidths { constraint.constant = -26 * s }
        refreshVerdicts()
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

    /// The contrast now, `nil` while Text or Background is empty; kept for `applyScale`.
    private var contrast: ColorContrast?

    /// Reflects the inspector: the colour in focus, Contrast, Favorites and Recent.
    func refresh() {
        let colors = inspector.colors
        let probe = inspector.probe
        // The pixel a click would pick, while the pointer is over the image: as it will be kept.
        let picked = isPicking && probe?.source == .viewer ? probe.flatMap(Self.picked) : nil
        refreshFocus(colors, probe: probe)
        refreshContrast(colors, picked: picked)
        let favoritesChanged = colors.favorites != shownFavorites
        shownFavorites = colors.favorites
        for button in favoriteButtons {
            let index = button.index
            let color = colors.favorites[index]
            let previewing = picked != nil && colors.target == .favorite(index)
            button.show(previewing ? picked : color, isPreview: previewing, isTarget: colors.target == .favorite(index))
            guard favoritesChanged else { continue }
            button.menu = color.map { colorMenu($0, then: [menuItem("Remove", #selector(removeFavorite(_:)), index)]) }
        }
        refreshRecent(colors.recent)
        for row in recentStack.arrangedSubviews.compactMap({ $0 as? RecentRow }) {
            row.isFocused = colors.focus == .recent(row.index)
        }
    }

    private static func picked(_ probe: PixelInspector.Probe) -> PickedColor? {
        probe.sample.map { PickedColor($0, x: probe.x, y: probe.y) }
    }

    private func refreshFocus(_ colors: ColorMeterState, probe: PixelInspector.Probe?) {
        let label: String
        var detail: String?
        let shown: (sample: ColorSample, native: String)?
        if let color = colors.focused {
            shown = (color.sample, "\(color.nativeValues)  \(color.nativeSpaceName)")
            switch colors.focus {
            case .recent: (label, detail) = ("Recent", "\(color.x), \(color.y)")
            case .favorite(let index): label = "Favorite \(index + 1)"
            case .contrast(let slot): (label, detail) = ("Contrast", slot.title)
            // The live pixel has no kept colour.
            case .live: label = ""
            }
        } else {
            switch probe?.source {
            case .viewer?: label = "Under the mouse in the Viewer"
            case .captureArea?: label = "Under the cursor in the Capture Area"
            case nil: label = "Point at a pixel"
            }
            detail = probe.map { "\($0.x), \($0.y)" }
            shown = probe?.sample.map { ($0, "\($0.nativeValues)  \($0.nativeSpaceName)") }
        }
        focusLabel.stringValue = label
        focusDetail.stringValue = detail.map { "· \($0)" } ?? ""
        focusHeader.toolTip = ([label] + (detail.map { [$0] } ?? [])).joined(separator: " · ")
        swatch.color = shown.map { NSColor(srgb: $0.sample) }
        for format in Format.allCases {
            let text = shown.map { value(format, sample: $0.sample, native: $0.native) }
            values[format] = text
            rows[format]?.show(text)
        }
    }

    private func value(_ format: Format, sample: ColorSample, native: String) -> String {
        switch format {
        case .hex: sample.hex
        case .css: sample.cssRGB
        case .swiftUI: sample.swiftUI
        case .appKit: sample.appKit
        case .native: native
        }
    }

    private func refreshContrast(_ colors: ColorMeterState, picked: PickedColor?) {
        var pair: [ColorMeterState.Slot: ColorSample] = [:]
        for button in slotButtons {
            let slot = button.slot
            let previewing = picked != nil && colors.target == .contrast(slot)
            let color = previewing ? picked : colors[slot]
            button.show(color, isPreview: previewing, isTarget: colors.target == .contrast(slot))
            pair[slot] = color?.sample
        }
        preview.colors = pair[.text].flatMap { text in pair[.background].map { (text, $0) } }
        contrast = preview.colors.map { ColorContrast(text: $0.text, background: $0.background) }
        ratioLabel.stringValue = contrast?.ratioText ?? "—"
        ratioLabel.setAccessibilityLabel(contrast.map { "Contrast ratio \($0.ratioText)" } ?? "No contrast ratio")
        swapButton.isEnabled = colors.text != nil || colors.background != nil
        hintLabel.stringValue = colors.hint
        refreshVerdicts()
    }

    /// "✓ Text AA Pass" or "✕ Text AA Fail": the glyph and the word, not the colour alone, say it.
    private func refreshVerdicts() {
        let size = NSFont.smallSystemFontSize * scale
        for (level, label) in zip(ColorContrast.Level.allCases, verdictLabels) {
            let passes = contrast?.passes(level)
            let glyph = passes.map { $0 ? "✓" : "✕" } ?? "–"
            let word = passes.map { $0 ? "Pass" : "Fail" }
            let glyphColor: NSColor = passes.map { $0 ? .systemGreen : .systemRed } ?? .tertiaryLabelColor
            let text = NSMutableAttributedString(
                string: glyph,
                attributes: [.font: NSFont.systemFont(ofSize: size, weight: .bold), .foregroundColor: glyphColor])
            text.append(
                NSAttributedString(
                    string: " \(level.title)",
                    attributes: [
                        .font: NSFont.systemFont(ofSize: size),
                        .foregroundColor: passes == nil ? NSColor.tertiaryLabelColor : .labelColor,
                    ]))
            if let word {
                text.append(
                    NSAttributedString(
                        string: " \(word)",
                        attributes: [
                            .font: NSFont.systemFont(ofSize: size, weight: .semibold),
                            .foregroundColor: NSColor.labelColor,
                        ]))
            }
            label.attributedStringValue = text
            label.setAccessibilityLabel("\(level.title): \(word ?? "no pair")")
        }
    }

    private func refreshRecent(_ recent: [PickedColor]) {
        clearButton.isHidden = recent.isEmpty
        recentHint.isHidden = !recent.isEmpty
        guard recent != shownRecent else { return }
        shownRecent = recent
        recentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, color) in recent.enumerated() {
            let row = RecentRow(color, index: index)
            row.target = self
            row.action = #selector(clickRecent(_:))
            row.menu = colorMenu(
                color,
                then: [
                    menuItem("Add to Favorites", #selector(addToFavorites(_:)), index),
                    menuItem("Remove", #selector(removeRecent(_:)), index),
                ])
            row.apply(scale: scale)
            recentStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: recentStack.widthAnchor).isActive = true
        }
    }

    // MARK: Menus

    /// Copy HEX, CSS, SwiftUI and AppKit, each with its value, then `items`.
    private func colorMenu(_ color: PickedColor, then items: [NSMenuItem]) -> NSMenu {
        let menu = NSMenu()
        let sample = color.sample
        let font = NSFont.menuFont(ofSize: 0)
        for (name, value) in [
            ("HEX", sample.hex), ("CSS", sample.cssRGB), ("SwiftUI", sample.swiftUI), ("AppKit", sample.appKit),
        ] {
            let item = menuItem("Copy \(name)", #selector(copyValue(_:)), 0)
            item.representedObject = value
            let title = NSMutableAttributedString(string: "Copy \(name)  ", attributes: [.font: font])
            title.append(
                NSAttributedString(
                    string: value, attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]))
            item.attributedTitle = title
            menu.addItem(item)
        }
        menu.addItem(.separator())
        for item in items { menu.addItem(item) }
        return menu
    }

    private func menuItem(_ title: String, _ action: Selector, _ tag: Int) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.tag = tag
        return item
    }

    // MARK: Actions

    @objc fileprivate func copyFormat(_ sender: NSButton) {
        guard let text = values[Format.allCases[sender.tag]] else { return }
        onCopy?(text, text)
    }

    @objc private func copyValue(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        onCopy?(text, text)
    }

    @objc private func clickContrastSlot(_ sender: ContrastSlotButton) {
        inspector.changeColors { $0.clickContrast(sender.slot) }
    }

    @objc private func swapContrast() {
        inspector.changeColors { $0.swap() }
    }

    @objc private func clickFavorite(_ sender: FavoriteButton) {
        inspector.changeColors { $0.clickFavorite(sender.index) }
    }

    @objc private func removeFavorite(_ sender: NSMenuItem) {
        inspector.changeColors { $0.removeFavorite(sender.tag) }
    }

    @objc private func clickRecent(_ sender: RecentRow) {
        inspector.changeColors { $0.clickRecent(sender.index) }
    }

    @objc private func addToFavorites(_ sender: NSMenuItem) {
        guard !inspector.changeColors({ $0.addToFavorites(recent: sender.tag) }) else { return }
        onFeedback?("Favorites are full")
    }

    @objc private func removeRecent(_ sender: NSMenuItem) {
        inspector.changeColors { $0.removeRecent(sender.tag) }
    }

    @objc private func clearRecent() {
        inspector.changeColors { $0.clearRecent() }
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
        // The value takes the space between the name and the button, so the buttons line up at the
        // right edge.
        value.setContentHuggingPriority(.defaultLow, for: .horizontal)
        copy.setContentHuggingPriority(.required, for: .horizontal)
        distribution = .fill
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

/// A button drawn by the panel, with views inside that don't take the click: a contrast slot, a
/// favourite, a recent colour.
private class ColorCellButton: NSButton {
    override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = false
        title = ""
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    // The labels and swatches inside are part of the button.
    override func hitTest(_ point: NSPoint) -> NSView? {
        !isHidden && frame.contains(point) ? self : nil
    }

    override func draw(_ dirtyRect: NSRect) {}

    override var focusRingMaskBounds: NSRect { bounds }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }

    /// The accent ring of the target, inside the bounds.
    func drawTargetRing(scale: CGFloat) {
        let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6 * scale, yRadius: 6 * scale)
        ring.lineWidth = 2
        NSColor.controlAccentColor.setStroke()
        ring.stroke()
    }
}

/// Text or Background: swatch, name and HEX. An accent ring marks the target; being in focus shows
/// only in the block at the top, as the ring already says the slot was clicked.
private final class ContrastSlotButton: ColorCellButton {
    let slot: ColorMeterState.Slot
    private var scale: CGFloat = 1
    private let swatch = SwatchView()
    private let name: NSTextField
    private let hex = NSTextField(labelWithString: "—")
    private let content = NSStackView()
    private let labels = NSStackView()
    private lazy var swatchSize = [
        swatch.widthAnchor.constraint(equalToConstant: 0), swatch.heightAnchor.constraint(equalToConstant: 0),
    ]
    private lazy var insets = [
        content.leadingAnchor.constraint(equalTo: leadingAnchor), content.topAnchor.constraint(equalTo: topAnchor),
        bottomAnchor.constraint(equalTo: content.bottomAnchor),
        trailingAnchor.constraint(greaterThanOrEqualTo: content.trailingAnchor),
    ]

    init(slot: ColorMeterState.Slot) {
        self.slot = slot
        name = NSTextField(labelWithString: slot.title)
        super.init(frame: .zero)
        setButtonType(.pushOnPushOff)
        name.textColor = .secondaryLabelColor
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 0
        for view in [name, hex] { labels.addArrangedSubview(view) }
        swatch.translatesAutoresizingMaskIntoConstraints = false
        for view in [swatch, labels] { content.addArrangedSubview(view) }
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate(swatchSize + insets)
    }

    func apply(scale s: CGFloat) {
        scale = s
        for constraint in swatchSize { constraint.constant = 24 * s }
        for constraint in insets { constraint.constant = 7 * s }
        name.font = .systemFont(ofSize: 10 * s)
        hex.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize * s, weight: .medium)
        content.spacing = 7 * s
        needsDisplay = true
    }

    /// `isPreview`: `color` is the pixel under the pointer, which a click would put here.
    func show(_ color: PickedColor?, isPreview: Bool, isTarget: Bool) {
        swatch.color = color.map { NSColor(picked: $0) }
        swatch.isPreview = isPreview
        hex.stringValue = color?.hex ?? "—"
        state = isTarget ? .on : .off
        setAccessibilityLabel("\(slot.title), \(color?.hex ?? "empty")")
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if state == .on {
            drawTargetRing(scale: scale)
        } else {
            let outline = NSBezierPath(
                roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6 * scale, yRadius: 6 * scale)
            NSColor.separatorColor.setStroke()
            outline.stroke()
        }
    }
}

/// One favourite: a square of its colour, or dashed with "+" while empty. An accent ring marks the
/// target; being in focus shows only in the block at the top, so the slot has one ring, the target's.
private final class FavoriteButton: ColorCellButton {
    let index: Int
    var scale: CGFloat = 1 {
        didSet { needsDisplay = true }
    }
    private var color: PickedColor?
    private var isPreview = false

    init(index: Int) {
        self.index = index
        super.init(frame: .zero)
        setButtonType(.pushOnPushOff)
    }

    func show(_ color: PickedColor?, isPreview: Bool, isTarget: Bool) {
        self.color = color
        self.isPreview = isPreview
        state = isTarget ? .on : .off
        setAccessibilityLabel("Favorite \(index + 1), \(color?.hex ?? "empty")")
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let inner = bounds.insetBy(dx: 3 * scale + 0.5, dy: 3 * scale + 0.5)
        let square = NSBezierPath(roundedRect: inner, xRadius: 4 * scale, yRadius: 4 * scale)
        if let color {
            NSColor(picked: color).setFill()
            square.fill()
        }
        if isPreview {
            square.setLineDash([3 * scale, 2 * scale], count: 2, phase: 0)
            square.lineWidth = 1.5
            NSColor.controlAccentColor.setStroke()
        } else if color == nil {
            square.setLineDash([3 * scale, 2 * scale], count: 2, phase: 0)
            NSColor.tertiaryLabelColor.setStroke()
            let plus = NSBezierPath()
            let arm = min(inner.width, inner.height) * 0.18
            plus.move(to: CGPoint(x: inner.midX - arm, y: inner.midY))
            plus.line(to: CGPoint(x: inner.midX + arm, y: inner.midY))
            plus.move(to: CGPoint(x: inner.midX, y: inner.midY - arm))
            plus.line(to: CGPoint(x: inner.midX, y: inner.midY + arm))
            plus.lineWidth = 1.5
            plus.stroke()
        } else {
            NSColor.separatorColor.setStroke()
        }
        square.stroke()
        if state == .on { drawTargetRing(scale: scale) }
    }
}

/// One recent colour: swatch, HEX and where it was picked; highlighted while in focus.
private final class RecentRow: ColorCellButton {
    let index: Int
    private let label: String
    private var scale: CGFloat = 1
    private let swatch = SwatchView()
    private let hex: NSTextField
    private let position: NSTextField
    private let content = NSStackView()
    private lazy var swatchSize = [
        swatch.widthAnchor.constraint(equalToConstant: 0), swatch.heightAnchor.constraint(equalToConstant: 0),
    ]
    private lazy var insets = [
        content.leadingAnchor.constraint(equalTo: leadingAnchor),
        trailingAnchor.constraint(equalTo: content.trailingAnchor),
        content.topAnchor.constraint(equalTo: topAnchor), bottomAnchor.constraint(equalTo: content.bottomAnchor),
    ]

    /// The colour in focus is this row's: highlighted, and VoiceOver says so.
    var isFocused = false {
        didSet {
            guard isFocused != oldValue else { return }
            setAccessibilityLabel(isFocused ? "\(label), in focus" : label)
            needsDisplay = true
        }
    }

    init(_ color: PickedColor, index: Int) {
        self.index = index
        label = "Recent \(color.hex) at \(color.x), \(color.y)"
        hex = NSTextField(labelWithString: color.hex)
        position = NSTextField(labelWithString: "\(color.x), \(color.y)")
        super.init(frame: .zero)
        swatch.color = NSColor(picked: color)
        swatch.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate(swatchSize)
        position.textColor = .secondaryLabelColor
        for view in [swatch, hex, position, NSView()] { content.addArrangedSubview(view) }
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate(insets)
        setAccessibilityLabel(label)
    }

    func apply(scale s: CGFloat) {
        scale = s
        for constraint in swatchSize { constraint.constant = 18 * s }
        for (i, constraint) in insets.enumerated() { constraint.constant = (i < 2 ? 4 : 2) * s }
        hex.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize * s, weight: .medium)
        position.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize * s, weight: .regular)
        content.spacing = 6 * s
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isFocused else { return }
        let row = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5 * scale, yRadius: 5 * scale)
        NSColor.quaternaryLabelColor.setFill()
        row.fill()
        NSColor.separatorColor.setStroke()
        row.stroke()
    }
}

/// "Aa" in the Text colour on the Background colour; placeholder greys while either is empty.
private final class ContrastPreview: NSView {
    var colors: (text: ColorSample, background: ColorSample)? {
        didSet { needsDisplay = true }
    }
    var scale: CGFloat = 1 {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6 * scale, yRadius: 6 * scale)
        (colors.map { NSColor(srgb: $0.background) } ?? .quaternaryLabelColor).setFill()
        box.fill()
        NSColor.separatorColor.setStroke()
        box.stroke()
        let text = NSAttributedString(
            string: "Aa",
            attributes: [
                .font: NSFont.systemFont(ofSize: 20 * scale, weight: .semibold),
                .foregroundColor: colors.map { NSColor(srgb: $0.text) } ?? .tertiaryLabelColor,
            ])
        let size = text.size()
        text.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
    }
}

extension NSColor {
    /// A sample's sRGB value with its opacity.
    fileprivate convenience init(srgb sample: ColorSample) {
        self.init(srgbRed: sample.srgb.red, green: sample.srgb.green, blue: sample.srgb.blue, alpha: sample.alpha)
    }

    fileprivate convenience init(picked color: PickedColor) {
        self.init(srgb: color.sample)
    }
}

/// A colour swatch with a hairline border, so white and near-background colours stay visible.
final class SwatchView: NSView {
    var color: NSColor? { didSet { needsDisplay = true } }
    /// Dashed in the accent colour: the colour a click would put here.
    var isPreview = false { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
        (color ?? NSColor.quaternaryLabelColor).setFill()
        path.fill()
        if isPreview {
            path.setLineDash([3, 2], count: 2, phase: 0)
            path.lineWidth = 1.5
            NSColor.controlAccentColor.setStroke()
        } else {
            NSColor.separatorColor.setStroke()
            path.lineWidth = 1
        }
        path.stroke()
    }
}
