import AppKit

/// The Viewer's zoom presets and zoom field, in the toolbar's look: Fit, 1×, 2×, 4×, 8× and 16× as
/// text buttons in one group, the one that matches the current zoom shown as a toggle that is on
/// (none between presets), and the current zoom in percent in a group of its own, where typing a
/// number and Return sets it. Side by side in the strip under the toolbar (`ViewerZoomStrip`), the
/// field's group a capsule as the toolbar's items are; one under another in the floating zoom panel
/// (`ZoomPanel`), as wide as the studio's palette with the groups centred, the field's group a
/// rounded rectangle, as a text field is.
@MainActor
final class ZoomControls: NSView, NSTextFieldDelegate {
    /// The field's width: "6400%" in the field's font, with room for the capsule's round ends.
    static let fieldWidth: CGFloat = 48

    /// Called when Return or Escape ends an edit of the field, to give the focus back to the image, so
    /// Space, `+`/`-` and Escape work there at once.
    var onDoneEditing: (() -> Void)?

    /// In `ZoomPanState.presetNames`' order.
    private let presetButtons: [PaletteButton]
    /// The current zoom in percent; typing a number and Return sets it.
    /// Leaving the field any other way drops what was typed.
    private let zoomField = ZoomField(string: "")
    /// The field's place in its group, as tall as a button; the floating panel lays the field over it
    /// from a window of its own (`ZoomPanel`).
    private(set) lazy var fieldSlot = ZoomFieldBox(field: zoomField)
    var field: ZoomField { zoomField }
    /// The zoom the field last showed, to tell a zoom change from a pan.
    private var shownZoom: CGFloat?
    private let zoomPan: ZoomPanController

    /// `insets`: around the groups, inside the view; `width`: the view's, the groups centred in it,
    /// or their own; `fieldGroupRadius`: the field's group's corners, or the capsule.
    init(
        zoomPan: ZoomPanController, orientation: NSUserInterfaceLayoutOrientation, insets: NSEdgeInsets,
        width: CGFloat? = nil, fieldGroupRadius: CGFloat? = nil
    ) {
        self.zoomPan = zoomPan
        presetButtons = ZoomPanState.presetNames.map { _ in PaletteButton() }
        super.init(frame: .zero)

        for (index, button) in presetButtons.enumerated() {
            let name = ZoomPanState.presetNames[index]
            button.show(text: name, name: index == 0 ? "Zoom to Fit" : "Zoom to \(name)")
            button.makeToggle()
            button.tag = index
            button.target = self
            button.action = #selector(presetClicked(_:))
        }

        let look = ToolbarLook.current
        zoomField.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        zoomField.alignment = .center
        zoomField.isBordered = false
        zoomField.drawsBackground = false
        zoomField.focusRingType = .none
        zoomField.toolTip = "Zoom — type a percentage and press Return"
        zoomField.setAccessibilityLabel("Zoom")
        zoomField.target = self
        zoomField.action = #selector(zoomEntered(_:))
        zoomField.cell?.sendsActionOnEndEditing = false
        zoomField.delegate = self
        // A slot as tall as a button's, the field centred in it.
        zoomField.translatesAutoresizingMaskIntoConstraints = false
        fieldSlot.addSubview(zoomField)
        NSLayoutConstraint.activate([
            fieldSlot.widthAnchor.constraint(equalToConstant: Self.fieldWidth),
            fieldSlot.heightAnchor.constraint(equalToConstant: look.buttonSize.height),
            zoomField.leadingAnchor.constraint(equalTo: fieldSlot.leadingAnchor),
            zoomField.trailingAnchor.constraint(equalTo: fieldSlot.trailingAnchor),
            zoomField.centerYAnchor.constraint(equalTo: fieldSlot.centerYAnchor),
        ])

        let stack = NSStackView(views: [
            look.group(presetButtons, orientation: orientation),
            look.group([fieldSlot], orientation: orientation, cornerRadius: fieldGroupRadius),
        ])
        stack.orientation = orientation
        stack.spacing = look.groupSpacing
        stack.edgeInsets = insets
        // Else a vertical stack's fitting width leaves out its side insets.
        stack.setHuggingPriority(.defaultHigh, for: .horizontal)
        if let width {
            stack.alignment = .centerX
            stack.widthAnchor.constraint(equalToConstant: width).isActive = true
        }
        let content = look.container(stack)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
        ])

        zoomPan.observe { [weak self] in self?.refresh() }
        refresh()
        // A new accent colour shows on the preset that is on.
        _ = NotificationCenter.default.addObserver(
            forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.presetButtons.forEach { $0.needsDisplay = true } }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Reflects the current zoom: the matching preset is on, and the field shows the percentage.
    private func refresh() {
        let state = zoomPan.state
        // A zoom set another way (Fit, a preset, a pinch) replaces a half-typed value.
        if state.zoom != shownZoom, zoomField.currentEditor() != nil {
            zoomField.abortEditing()
        }
        shownZoom = state.zoom
        if zoomField.currentEditor() == nil {
            zoomField.stringValue = "\(Int((state.zoom * 100).rounded()))%"
        }
        let preset = state.preset
        for (index, button) in presetButtons.enumerated() {
            button.state = index == preset ? .on : .off
        }
    }

    /// Shows the zoom, not the click: a click on the preset that is on flips it off although the
    /// zoom stays.
    @objc private func presetClicked(_ sender: NSButton) {
        zoomPan.zoom(toPreset: sender.tag)
        refresh()
    }

    @objc private func zoomEntered(_ sender: NSTextField) {
        let digits = sender.stringValue.filter { $0.isNumber || $0 == "." || $0 == "," }
            .replacingOccurrences(of: ",", with: ".")
        if let percent = Double(digits), percent > 0 {
            zoomPan.setZoom(CGFloat(percent / 100))
        }
        sender.window?.makeFirstResponder(nil)
        refresh()
        onDoneEditing?()
    }

    /// Escape drops what was typed and shows the current zoom again.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        zoomField.abortEditing()
        shownZoom = nil
        refresh()
        onDoneEditing?()
        return true
    }

    /// Focus left the field without Return: show the current zoom again.
    func controlTextDidEndEditing(_ notification: Notification) {
        // The field editor is detached only after this notification.
        DispatchQueue.main.async { [weak self] in
            self?.shownZoom = nil
            self?.refresh()
        }
    }
}

/// The zoom field: a click on it, while it isn't being edited, starts the edit with the whole value
/// selected, so typing replaces it, rather than placing the caret; once editing, clicks go to the
/// field editor as in any field. Becoming first responder any other way — Tab, the window making it
/// so — also selects the whole value.
final class ZoomField: NSTextField {
    /// Starts editing, its window made key first so the keys reach it, with the whole value selected;
    /// while already editing, selects it all again.
    func beginEditing() {
        guard let window else { return }
        if currentEditor() == nil {
            window.makeKey()
            window.makeFirstResponder(self)
        }
        currentEditor()?.selectAll(nil)
    }

    /// Not passed on: the field editor's own tracking would put the caret where the click was.
    override func mouseDown(with event: NSEvent) {
        beginEditing()
    }

    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        currentEditor()?.selectAll(nil)
        return true
    }
}

/// The zoom field's group, as tall as a button: a click anywhere in it, not only on the digits,
/// starts the field's edit (`ZoomField.beginEditing`), and doesn't drag the window it is in. In
/// the strip it holds the field; in the floating panel, the field's own window holds one over it
/// (`ZoomPanel`).
final class ZoomFieldBox: NSView {
    private weak var field: ZoomField?

    init(field: ZoomField) {
        self.field = field
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// As the field's own: a click on the box makes the field's window key, which a window that
    /// becomes key only if needed (`ZoomPanel`'s field window) otherwise refuses.
    override var needsPanelToBecomeKey: Bool { true }
    override func mouseDown(with event: NSEvent) { field?.beginEditing() }
}
