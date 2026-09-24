import AppKit

/// The Viewer's toolbar (docs/product.md, Viewer): zoom presets and the current zoom on the left; Freeze,
/// the Ruler, the Grid, Crosshair and Color Meter toggles, Copy, Save and the keep-on-top pin on the right.
///
/// Every item has a menu form, so when a narrow window moves items into the overflow (») menu they
/// stay usable: Zoom becomes a submenu of presets, the buttons become commands, the pin a checkmark.
@MainActor
final class ViewerToolbar: NSObject, NSToolbarDelegate, NSTextFieldDelegate {
    private static let presetsID = NSToolbarItem.Identifier("zoomPresets")
    private static let zoomLabelID = NSToolbarItem.Identifier("zoomLabel")
    private static let freezeID = NSToolbarItem.Identifier("freeze")
    private static let rulerID = NSToolbarItem.Identifier("ruler")
    private static let gridID = NSToolbarItem.Identifier("grid")
    private static let crosshairID = NSToolbarItem.Identifier("crosshair")
    private static let meterID = NSToolbarItem.Identifier("colorMeter")
    private static let referencesID = NSToolbarItem.Identifier("references")
    private static let copyID = NSToolbarItem.Identifier("copyView")
    private static let saveID = NSToolbarItem.Identifier("saveView")
    private static let onTopID = NSToolbarItem.Identifier("alwaysOnTop")

    var onToggleAlwaysOnTop: (() -> Void)?
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onToggleFreeze: (() -> Void)?
    var onToggleRuler: (() -> Void)?

    enum Toggle: CaseIterable {
        case grid, crosshair, meter, references

        var title: String {
            switch self {
            case .grid: "Pixel Grid"
            case .crosshair: "Crosshair"
            case .meter: "Color Meter"
            case .references: "References"
            }
        }

        var symbol: String {
            switch self {
            case .grid: "grid"
            case .crosshair: "scope"
            case .meter: "eyedropper"
            case .references: "square.stack.3d.up"
            }
        }
    }

    var onToggle: ((Toggle) -> Void)?
    private var toggleButtons: [Toggle: NSButton] = [:]
    private var toggleMenuItems: [Toggle: NSMenuItem] = [:]

    /// Segment 0 is Fit; the rest are `ZoomPanState.presets`.
    private static let presetTitles = ["Fit"] + ZoomPanState.presets.map { "\(Int($0))×" }
    private let presets = NSSegmentedControl(
        labels: presetTitles, trackingMode: .selectOne, target: nil, action: nil)
    /// The current zoom in percent; typing a number and Return sets it (docs/product.md, Zoom and pan).
    /// Leaving the field any other way drops what was typed.
    private let zoomLabel = NSTextField(string: "")
    /// The zoom the label last showed, to tell a zoom change from a pan.
    private var shownZoom: CGFloat?
    var onZoomEntered: ((CGFloat) -> Void)?
    private let freezeButton = NSButton()
    private let rulerButton = NSButton()
    private let rulerMenuItem = NSMenuItem(title: "Ruler", action: nil, keyEquivalent: "")
    private let freezeMenuItem = NSMenuItem(title: "Freeze Frame", action: nil, keyEquivalent: "")
    private let onTopButton = NSButton()
    private let copyButton = NSButton()
    private let saveButton = NSButton()

    /// The overflow-menu forms.
    private let presetsMenuItem = NSMenuItem(title: "Zoom", action: nil, keyEquivalent: "")
    private let zoomLabelMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let onTopMenuItem = NSMenuItem(title: "Keep on Top", action: nil, keyEquivalent: "")

    private let zoomPan: ZoomPanController
    let toolbar = NSToolbar(identifier: "Viewer")

    init(zoomPan: ZoomPanController) {
        self.zoomPan = zoomPan
        super.init()
        presets.target = self
        presets.action = #selector(presetChosen(_:))
        presets.segmentStyle = .separated
        for index in 0..<presets.segmentCount {
            presets.setWidth(index == 0 ? 40 : 34, forSegment: index)
        }
        zoomLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        zoomLabel.alignment = .right
        zoomLabel.bezelStyle = .roundedBezel
        zoomLabel.controlSize = .small
        zoomLabel.toolTip = "Zoom — type a percentage and press Return"
        zoomLabel.target = self
        zoomLabel.action = #selector(zoomEntered(_:))
        zoomLabel.cell?.sendsActionOnEndEditing = false
        zoomLabel.delegate = self
        zoomLabel.widthAnchor.constraint(equalToConstant: 64).isActive = true

        configure(copyButton, symbol: "doc.on.doc", title: "Copy View", action: #selector(copyClicked))
        configure(saveButton, symbol: "square.and.arrow.down", title: "Save View…", action: #selector(saveClicked))
        configure(onTopButton, symbol: "pin", title: "Keep on Top", action: #selector(onTopClicked))
        onTopButton.setButtonType(.pushOnPushOff)
        configure(freezeButton, symbol: "pause", title: "Freeze Frame (Space)", action: #selector(freezeClicked))
        freezeButton.setButtonType(.pushOnPushOff)
        freezeMenuItem.target = self
        freezeMenuItem.action = #selector(freezeClicked)
        configure(rulerButton, symbol: "ruler", title: "Ruler", action: #selector(rulerClicked))
        rulerButton.setButtonType(.pushOnPushOff)
        rulerMenuItem.target = self
        rulerMenuItem.action = #selector(rulerClicked)
        for toggle in Toggle.allCases {
            let button = NSButton()
            configure(button, symbol: toggle.symbol, title: toggle.title, action: #selector(toggleClicked(_:)))
            button.setButtonType(.pushOnPushOff)
            button.tag = Toggle.allCases.firstIndex(of: toggle) ?? 0
            toggleButtons[toggle] = button
            let item = NSMenuItem(title: toggle.title, action: #selector(toggleClicked(_:)), keyEquivalent: "")
            item.target = self
            item.tag = button.tag
            toggleMenuItems[toggle] = item
        }
        onTopButton.alternateImage = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Keep on Top")

        let presetsMenu = NSMenu()
        for (index, title) in Self.presetTitles.enumerated() {
            let item = presetsMenu.addItem(withTitle: title, action: #selector(presetMenuChosen(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
        }
        presetsMenuItem.submenu = presetsMenu
        zoomLabelMenuItem.isEnabled = false
        onTopMenuItem.target = self
        onTopMenuItem.action = #selector(onTopClicked)

        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        refresh()
    }

    private func configure(_ button: NSButton, symbol: String, title: String, action: Selector) {
        button.bezelStyle = .toolbar
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.toolTip = title
        button.target = self
        button.action = action
    }

    /// Reflects the current zoom: the matching preset is selected, and the label shows the percentage.
    func refresh() {
        let state = zoomPan.state
        let percent = "\(Int((state.zoom * 100).rounded()))%"
        // A zoom set another way (Fit, a preset, a pinch) replaces a half-typed value.
        if state.zoom != shownZoom, zoomLabel.currentEditor() != nil {
            zoomLabel.abortEditing()
        }
        shownZoom = state.zoom
        if zoomLabel.currentEditor() == nil {
            zoomLabel.stringValue = percent
        }
        zoomLabelMenuItem.title = "Zoom: \(percent)"
        let selected: Int
        if zoomPan.isFit {
            selected = 0
        } else if let index = ZoomPanState.presets.firstIndex(where: { abs($0 - state.zoom) < 0.0001 }) {
            selected = index + 1
        } else {
            selected = -1
        }
        presets.selectedSegment = selected
        for item in presetsMenuItem.submenu?.items ?? [] {
            item.state = item.tag == selected ? .on : .off
        }
    }

    @objc private func zoomEntered(_ sender: NSTextField) {
        let digits = sender.stringValue.filter { $0.isNumber || $0 == "." || $0 == "," }
            .replacingOccurrences(of: ",", with: ".")
        if let percent = Double(digits), percent > 0 {
            onZoomEntered?(CGFloat(percent / 100))
        }
        sender.window?.makeFirstResponder(nil)
        refresh()
    }

    /// Focus left the field without Return: show the current zoom again.
    func controlTextDidEndEditing(_ notification: Notification) {
        // The field editor is detached only after this notification.
        DispatchQueue.main.async { [weak self] in
            self?.shownZoom = nil
            self?.refresh()
        }
    }

    func setToggle(_ toggle: Toggle, isOn: Bool) {
        toggleButtons[toggle]?.state = isOn ? .on : .off
        toggleMenuItems[toggle]?.state = isOn ? .on : .off
    }

    @objc private func toggleClicked(_ sender: Any) {
        let tag = (sender as? NSButton)?.tag ?? (sender as? NSMenuItem)?.tag ?? 0
        onToggle?(Toggle.allCases[tag])
    }

    func setRuler(_ isOn: Bool) {
        rulerButton.state = isOn ? .on : .off
        rulerMenuItem.state = isOn ? .on : .off
    }

    func setFrozen(_ isOn: Bool) {
        freezeButton.state = isOn ? .on : .off
        freezeMenuItem.state = isOn ? .on : .off
    }

    func setAlwaysOnTop(_ isOn: Bool) {
        onTopButton.state = isOn ? .on : .off
        onTopMenuItem.state = isOn ? .on : .off
    }

    // MARK: Actions

    @objc private func onTopClicked() { onToggleAlwaysOnTop?() }
    /// The push-on-push-off button flips itself on click; it shows the frozen state only from
    /// `setFrozen`, since there may be nothing to freeze yet.
    @objc private func freezeClicked() {
        freezeButton.state = freezeMenuItem.state
        onToggleFreeze?()
    }
    @objc private func rulerClicked() { onToggleRuler?() }
    @objc private func copyClicked() { onCopy?() }
    @objc private func saveClicked() { onSave?() }

    @objc private func presetChosen(_ sender: NSSegmentedControl) {
        choosePreset(sender.selectedSegment)
    }

    @objc private func presetMenuChosen(_ sender: NSMenuItem) {
        choosePreset(sender.tag)
    }

    private func choosePreset(_ index: Int) {
        if index == 0 {
            zoomPan.fit()
        } else if index > 0 {
            zoomPan.setZoom(ZoomPanState.presets[index - 1])
        }
    }

    // MARK: NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            Self.presetsID, Self.zoomLabelID, .flexibleSpace, Self.freezeID, Self.rulerID, Self.gridID,
            Self.crosshairID,
            Self.meterID, Self.referencesID, .space,
            Self.copyID, Self.saveID, Self.onTopID,
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        switch identifier {
        case Self.presetsID:
            item.view = presets
            item.label = "Zoom"
            item.menuFormRepresentation = presetsMenuItem
        case Self.zoomLabelID:
            item.view = zoomLabel
            item.menuFormRepresentation = zoomLabelMenuItem
        case Self.freezeID:
            item.view = freezeButton
            item.label = "Freeze Frame"
            item.menuFormRepresentation = freezeMenuItem
        case Self.rulerID:
            item.view = rulerButton
            item.label = "Ruler"
            item.menuFormRepresentation = rulerMenuItem
        case Self.gridID, Self.crosshairID, Self.meterID, Self.referencesID:
            let toggles: [NSToolbarItem.Identifier: Toggle] = [
                Self.gridID: .grid, Self.crosshairID: .crosshair, Self.meterID: .meter, Self.referencesID: .references,
            ]
            let toggle = toggles[identifier] ?? .grid
            item.view = toggleButtons[toggle]
            item.label = toggle.title
            item.menuFormRepresentation = toggleMenuItems[toggle]
        case Self.copyID:
            item.view = copyButton
            item.label = "Copy View"
            item.menuFormRepresentation = commandItem("Copy View", #selector(copyClicked))
        case Self.saveID:
            item.view = saveButton
            item.label = "Save View…"
            item.menuFormRepresentation = commandItem("Save View…", #selector(saveClicked))
        case Self.onTopID:
            item.view = onTopButton
            item.label = "Keep on Top"
            item.menuFormRepresentation = onTopMenuItem
        default:
            return nil
        }
        return item
    }

    private func commandItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }
}
