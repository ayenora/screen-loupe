import AppKit

/// The Viewer's toolbar (docs/product.md, Viewer): zoom presets and the current zoom on the left; Freeze
/// with its menu of delays, the Select tool, the Ruler, the Grid toggle, the pointer toggle with its
/// menu of styles, the Color Meter, References and Recent Captures toggles, Copy, Save and the
/// keep-on-top pin on the right.
///
/// Every item has a menu form, so when a narrow window moves items into the overflow (») menu they
/// stay usable: Zoom becomes a submenu of presets, the buttons become commands, the pin a checkmark.
///
/// Freeze, Select, Ruler, Copy, Save and Keep on Top are app commands: they go up the responder chain to
/// `AppController`, as the menus' do. The toggles are settings and change them directly. Every
/// button shows the state of its model, never just its own click.
@MainActor
final class ViewerToolbar: NSObject, NSToolbarDelegate, NSTextFieldDelegate {
    private static let presetsID = NSToolbarItem.Identifier("zoomPresets")
    private static let zoomLabelID = NSToolbarItem.Identifier("zoomLabel")
    private static let freezeID = NSToolbarItem.Identifier("freeze")
    private static let selectID = NSToolbarItem.Identifier("select")
    private static let rulerID = NSToolbarItem.Identifier("ruler")
    private static let gridID = NSToolbarItem.Identifier("grid")
    private static let crosshairID = NSToolbarItem.Identifier("crosshair")
    private static let meterID = NSToolbarItem.Identifier("colorMeter")
    private static let referencesID = NSToolbarItem.Identifier("references")
    private static let capturesID = NSToolbarItem.Identifier("recentCaptures")
    private static let copyID = NSToolbarItem.Identifier("copyView")
    private static let saveID = NSToolbarItem.Identifier("saveView")
    private static let onTopID = NSToolbarItem.Identifier("alwaysOnTop")

    private enum Toggle: CaseIterable {
        case grid, crosshair, meter, references, captures

        var title: String {
            switch self {
            case .grid: "Pixel Grid"
            case .crosshair: "Crosshair"
            case .meter: "Color Meter"
            case .references: "References"
            case .captures: "Recent Captures"
            }
        }

        var symbol: String {
            switch self {
            case .grid: "grid"
            case .crosshair: "scope"
            case .meter: "eyedropper"
            case .references: "square.stack.3d.up"
            case .captures: "photo"
            }
        }
    }

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
    private let freezeButton = NSButton()
    /// The ▾ beside the pause button: Freeze Now and Freeze in 3, 5 or 10 seconds.
    private let freezeMenuButton = NSButton()
    /// The ▾ beside the pointer toggle: Crosshair, Cursor or Original Cursor in the Capture.
    private let pointerMenuButton = NSButton()
    private let selectButton = NSButton()
    private let selectMenuItem = NSMenuItem(title: "Select", action: nil, keyEquivalent: "")
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
    private let settings: SettingsStore
    private let ruler: RulerController
    private let selection: SelectionController
    /// Frozen or counting down to a freeze, as `setFrozen` last reported it.
    private var isFrozen = false
    let toolbar = NSToolbar(identifier: "Viewer")

    init(zoomPan: ZoomPanController, settings: SettingsStore, ruler: RulerController, selection: SelectionController) {
        self.zoomPan = zoomPan
        self.settings = settings
        self.ruler = ruler
        self.selection = selection
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

        configure(copyButton, symbol: "doc.on.doc", title: "Copy View (⌘C)", action: #selector(copyClicked(_:)))
        configure(
            saveButton, symbol: "square.and.arrow.down", title: "Save View… (⌘S)", action: #selector(saveClicked(_:)))
        configure(onTopButton, symbol: "pin", title: "Keep on Top", action: #selector(onTopClicked(_:)))
        onTopButton.setButtonType(.pushOnPushOff)
        configure(freezeButton, symbol: "pause", title: "Freeze Frame (Space)", action: #selector(freezeClicked(_:)))
        freezeButton.setButtonType(.pushOnPushOff)
        configure(
            freezeMenuButton, symbol: "chevron.down", title: "Freeze Later", action: #selector(freezeMenuClicked(_:)))
        freezeMenuButton.image = freezeMenuButton.image?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 8, weight: .semibold))
        freezeMenuButton.widthAnchor.constraint(equalToConstant: 16).isActive = true
        freezeMenuItem.submenu = Self.freezeMenu(withToggle: true)
        configure(
            pointerMenuButton, symbol: "chevron.down", title: "Crosshair or Cursor",
            action: #selector(pointerMenuClicked(_:)))
        pointerMenuButton.image = pointerMenuButton.image?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 8, weight: .semibold))
        pointerMenuButton.widthAnchor.constraint(equalToConstant: 16).isActive = true
        configure(
            selectButton, symbol: "rectangle.dashed", title: "Select (⌘E) — drag to select, ⌘C copies it",
            action: #selector(selectClicked(_:)))
        selectButton.setButtonType(.pushOnPushOff)
        selectMenuItem.action = #selector(AppController.toggleSelectTool(_:))
        configure(rulerButton, symbol: "ruler", title: "Ruler (⌘R)", action: #selector(rulerClicked(_:)))
        rulerButton.setButtonType(.pushOnPushOff)
        rulerMenuItem.action = #selector(AppController.toggleMeasuringRuler(_:))
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
        onTopMenuItem.action = #selector(AppController.toggleViewerAlwaysOnTop(_:))

        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        zoomPan.observe { [weak self] in self?.refresh() }
        refresh()
        ruler.observe { [weak self] in self?.showRuler() }
        showRuler()
        selection.observe { [weak self] in self?.showSelectTool() }
        showSelectTool()
        settings.observe(\.viewerAlwaysOnTop) { [weak self] in self?.show($0, on: self?.onTopButton) }
        settings.observe(\.gridEnabled) { [weak self] in self?.showToggle(.grid, isOn: $0) }
        settings.observe(\.crosshairEnabled) { [weak self] in self?.showToggle(.crosshair, isOn: $0) }
        settings.observe(\.meterVisible) { [weak self] in self?.showToggle(.meter, isOn: $0) }
        settings.observe(\.referencesVisible) { [weak self] in self?.showToggle(.references, isOn: $0) }
        settings.observe(\.capturesVisible) { [weak self] in self?.showToggle(.captures, isOn: $0) }
        settings.observe(\.pointerStyle) { [weak self] in self?.showPointerStyle($0) }
    }

    private func configure(_ button: NSButton, symbol: String, title: String, action: Selector) {
        button.bezelStyle = .toolbar
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.toolTip = title
        button.target = self
        button.action = action
    }

    /// Reflects the current zoom: the matching preset is selected, and the label shows the percentage.
    private func refresh() {
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
            zoomPan.setZoom(CGFloat(percent / 100))
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

    private func show(_ isOn: Bool, on button: NSButton?) {
        button?.state = isOn ? .on : .off
    }

    private func showToggle(_ toggle: Toggle, isOn: Bool) {
        show(isOn, on: toggleButtons[toggle])
        toggleMenuItems[toggle]?.state = isOn ? .on : .off
    }

    private func showRuler() {
        show(ruler.isOn, on: rulerButton)
    }

    private func showSelectTool() {
        show(selection.isToolOn, on: selectButton)
    }

    /// Freeze Now and the delays, as `AppController` commands, which also enable them; the overflow
    /// form starts with the Freeze toggle itself.
    private static func freezeMenu(withToggle: Bool) -> NSMenu {
        let menu = NSMenu()
        if withToggle {
            menu.addItem(
                withTitle: "Freeze Frame", action: #selector(AppController.toggleFreeze(_:)), keyEquivalent: "")
        } else {
            menu.addItem(withTitle: "Freeze Now", action: #selector(AppController.freezeNow(_:)), keyEquivalent: "")
        }
        menu.addItem(.separator())
        for seconds in [3, 5, 10] {
            let item = menu.addItem(
                withTitle: "Freeze in \(seconds) Seconds", action: #selector(AppController.freezeAfterDelay(_:)),
                keyEquivalent: "")
            item.tag = seconds
        }
        return menu
    }

    func setFrozen(_ isOn: Bool) {
        isFrozen = isOn
        show(isOn, on: freezeButton)
    }

    /// While a recent capture shows, Freeze and the pointer have nothing to act on (docs/product.md,
    /// Recent Captures).
    func setShowingCapture(_ isShowing: Bool) {
        for button in [freezeButton, freezeMenuButton, toggleButtons[.crosshair], pointerMenuButton] {
            button?.isEnabled = !isShowing
        }
        toggleMenuItems[.crosshair]?.isHidden = isShowing
    }

    // MARK: Pointer

    private static func pointerTitle(_ style: PointerStyle) -> String {
        switch style {
        case .crosshair: "Crosshair"
        case .cursor: "Cursor"
        case .capturedCursor: "Original Cursor in the Capture"
        }
    }

    /// The toggle's icon and name follow the chosen style.
    private func showPointerStyle(_ style: PointerStyle) {
        let symbol =
            switch style {
            case .crosshair: "scope"
            case .cursor: "cursorarrow"
            case .capturedCursor: "cursorarrow.rays"
            }
        let title = Self.pointerTitle(style)
        let button = toggleButtons[.crosshair]
        button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button?.toolTip = title
        toggleMenuItems[.crosshair]?.title = title
    }

    /// The styles, the chosen one checked. The capture leaves the pointer out while the eyedropper
    /// is on, and the item says so.
    @objc private func pointerMenuClicked(_ sender: NSButton) {
        let menu = NSMenu()
        let current = settings.settings
        for (index, style) in PointerStyle.allCases.enumerated() {
            var title = Self.pointerTitle(style)
            if style == .capturedCursor, current.sidePanelLayout.isMeterExpanded {
                title += " — paused while the eyedropper is on"
            }
            let item = menu.addItem(withTitle: title, action: #selector(pointerChosen(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = style == current.pointerStyle ? .on : .off
        }
        let below = NSPoint(
            x: -(toggleButtons[.crosshair]?.frame.width ?? 0), y: sender.isFlipped ? sender.bounds.maxY + 4 : -4)
        menu.popUp(positioning: nil, at: below, in: sender)
    }

    /// Choosing a style also shows the pointer.
    @objc private func pointerChosen(_ sender: NSMenuItem) {
        let style = PointerStyle.allCases[sender.tag]
        settings.update {
            $0.pointerStyle = style
            $0.crosshairEnabled = true
        }
    }

    // MARK: Actions

    @objc private func toggleClicked(_ sender: Any) {
        let tag = (sender as? NSButton)?.tag ?? (sender as? NSMenuItem)?.tag ?? 0
        settings.update {
            switch Toggle.allCases[tag] {
            case .grid: $0.gridEnabled.toggle()
            case .crosshair: $0.crosshairEnabled.toggle()
            case .meter:
                $0.meterVisible.toggle()
                if $0.meterVisible { $0.expandedSidePanel = .colorMeter }
            case .references:
                // References and Recent Captures take turns in the column.
                $0.referencesVisible.toggle()
                if $0.referencesVisible {
                    $0.capturesVisible = false
                    $0.expandedSidePanel = .references
                }
            case .captures:
                $0.capturesVisible.toggle()
                if $0.capturesVisible {
                    $0.referencesVisible = false
                    $0.expandedSidePanel = .captures
                }
            }
        }
    }

    /// A push-on-push-off button flips itself when clicked; it goes back to its model's state
    /// (`isOn`) before the command runs, since the command may not change it (nothing to freeze
    /// yet). The model then reports the new state.
    private func send(_ action: Selector, from button: NSButton, isOn: Bool) {
        show(isOn, on: button)
        NSApp.sendAction(action, to: nil, from: button)
    }

    @objc private func freezeClicked(_ sender: NSButton) {
        send(#selector(AppController.toggleFreeze(_:)), from: sender, isOn: isFrozen)
    }

    @objc private func freezeMenuClicked(_ sender: NSButton) {
        let below = NSPoint(x: -freezeButton.frame.width, y: sender.isFlipped ? sender.bounds.maxY + 4 : -4)
        Self.freezeMenu(withToggle: false).popUp(positioning: nil, at: below, in: sender)
    }

    @objc private func selectClicked(_ sender: NSButton) {
        send(#selector(AppController.toggleSelectTool(_:)), from: sender, isOn: selection.isToolOn)
    }

    @objc private func rulerClicked(_ sender: NSButton) {
        send(#selector(AppController.toggleMeasuringRuler(_:)), from: sender, isOn: ruler.isOn)
    }

    @objc private func onTopClicked(_ sender: NSButton) {
        send(
            #selector(AppController.toggleViewerAlwaysOnTop(_:)), from: sender,
            isOn: settings.settings.viewerAlwaysOnTop)
    }

    @objc private func copyClicked(_ sender: NSButton) {
        NSApp.sendAction(#selector(AppController.copyView(_:)), to: nil, from: sender)
    }

    @objc private func saveClicked(_ sender: NSButton) {
        NSApp.sendAction(#selector(AppController.saveView(_:)), to: nil, from: sender)
    }

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
            Self.presetsID, Self.zoomLabelID, .flexibleSpace, Self.freezeID, Self.selectID, Self.rulerID, Self.gridID,
            Self.crosshairID,
            Self.meterID, Self.referencesID, Self.capturesID, .space,
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
            let group = NSStackView(views: [freezeButton, freezeMenuButton])
            group.spacing = 0
            item.view = group
            item.label = "Freeze Frame"
            item.menuFormRepresentation = freezeMenuItem
        case Self.selectID:
            item.view = selectButton
            item.label = "Select"
            item.menuFormRepresentation = selectMenuItem
        case Self.rulerID:
            item.view = rulerButton
            item.label = "Ruler"
            item.menuFormRepresentation = rulerMenuItem
        case Self.crosshairID:
            let group = NSStackView(views: [toggleButtons[.crosshair], pointerMenuButton].compactMap { $0 })
            group.spacing = 0
            item.view = group
            item.label = "Pointer"
            item.menuFormRepresentation = toggleMenuItems[.crosshair]
        case Self.gridID, Self.meterID, Self.referencesID, Self.capturesID:
            let toggles: [NSToolbarItem.Identifier: Toggle] = [
                Self.gridID: .grid, Self.meterID: .meter, Self.referencesID: .references, Self.capturesID: .captures,
            ]
            let toggle = toggles[identifier] ?? .grid
            item.view = toggleButtons[toggle]
            item.label = toggle.title
            item.menuFormRepresentation = toggleMenuItems[toggle]
        case Self.copyID:
            item.view = copyButton
            item.label = "Copy View"
            // An `AppController` command, which also enables it.
            item.menuFormRepresentation = NSMenuItem(
                title: "Copy View", action: #selector(AppController.copyView(_:)), keyEquivalent: "")
        case Self.saveID:
            item.view = saveButton
            item.label = "Save View…"
            item.menuFormRepresentation = NSMenuItem(
                title: "Save View…", action: #selector(AppController.saveView(_:)), keyEquivalent: "")
        case Self.onTopID:
            item.view = onTopButton
            item.label = "Keep on Top"
            item.menuFormRepresentation = onTopMenuItem
        default:
            return nil
        }
        return item
    }

}
