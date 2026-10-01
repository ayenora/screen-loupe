import AppKit

/// The Viewer's zoom presets and zoom field, in the toolbar's look: Fit, 1×, 2×, 4×, 8× and 16× as
/// text buttons in one group, the one that matches the current zoom shown as a toggle that is on
/// (none between presets), and the current zoom in percent in a group of its own, where typing a
/// number and Return sets it. Side by side in the strip under the toolbar (`ViewerZoomStrip`), one
/// under another in the floating zoom panel (`ZoomPanel`).
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
    private let zoomField = NSTextField(string: "")
    /// The zoom the field last showed, to tell a zoom change from a pan.
    private var shownZoom: CGFloat?
    private let zoomPan: ZoomPanController

    /// `insets`: around the groups, inside the view.
    init(zoomPan: ZoomPanController, orientation: NSUserInterfaceLayoutOrientation, insets: NSEdgeInsets) {
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
        let fieldSlot = NSView()
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
            look.group(presetButtons, orientation: orientation), look.group([fieldSlot], orientation: orientation),
        ])
        stack.orientation = orientation
        stack.spacing = look.groupSpacing
        stack.edgeInsets = insets
        // Else a vertical stack's fitting width leaves out its side insets.
        stack.setHuggingPriority(.defaultHigh, for: .horizontal)
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
