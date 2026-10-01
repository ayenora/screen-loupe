import AppKit

/// The Viewer's toolbar: the loupe, which shows the zoom panel, with its menu of the zoom presets and
/// the panel's styles, Freeze with its menu of delays, the Select tool, the Ruler with its menu
/// of rulers, the Grid toggle, the pointer toggle with its menu of styles, the colour vision
/// simulation with its menu of modes, the side panels (Color Meter, References, Recent Captures) as
/// one segmented control, Copy and Save each with its menu of the view and the source, and the
/// keep-on-top pin on the right. The zoom panel itself is a strip under the toolbar
/// (`ViewerZoomStrip`) or a panel beside the Viewer (`ZoomPanel`).
///
/// Every item has a menu form, so when a narrow window moves items into the overflow (») menu they
/// stay usable: the buttons become commands, the loupe a submenu of its toggle, the presets and the
/// styles, the Ruler a submenu of its two rulers, the simulation a submenu of its toggle and modes,
/// the panels a submenu of their toggles, the pin a checkmark.
///
/// The loupe, Freeze, Select, Ruler, the simulation, Copy, Save and Keep on Top are app commands: they go up the
/// responder chain to `AppController`, as the menus' do. The toggles are settings and change them directly. Every
/// button and segment shows the state of its model, never just its own click.
@MainActor
final class ViewerToolbar: NSObject, NSToolbarDelegate {
    private static let zoomID = NSToolbarItem.Identifier("zoomPanel")
    private static let freezeID = NSToolbarItem.Identifier("freeze")
    private static let selectID = NSToolbarItem.Identifier("select")
    private static let rulerID = NSToolbarItem.Identifier("ruler")
    private static let gridID = NSToolbarItem.Identifier("grid")
    private static let crosshairID = NSToolbarItem.Identifier("crosshair")
    private static let visionID = NSToolbarItem.Identifier("colorVision")
    private static let panelsID = NSToolbarItem.Identifier("sidePanels")
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

        /// The side panels, in the order of their segments.
        static let panels: [Toggle] = [.meter, .references, .captures]
    }

    /// Grid and the pointer; the panels are segments of `panels`.
    private var toggleButtons: [Toggle: NSButton] = [:]
    private var toggleMenuItems: [Toggle: NSMenuItem] = [:]
    private let panels = NSSegmentedControl(
        images: Toggle.panels.map {
            NSImage(systemSymbolName: $0.symbol, accessibilityDescription: $0.title) ?? NSImage()
        },
        trackingMode: .selectAny, target: nil, action: nil)
    private let panelsMenuItem = NSMenuItem(title: "Panels", action: nil, keyEquivalent: "")

    private let zoomButton = NSButton()
    /// The ▾ beside the loupe: the zoom presets and the zoom panel's styles.
    private let zoomMenuButton = NSButton()
    private let zoomMenuItem = NSMenuItem(title: "Zoom", action: nil, keyEquivalent: "")
    private let freezeButton = NSButton()
    /// The ▾ beside the pause button: Freeze Now, Freeze in 3, 5 or 10 seconds, and Use Frozen Frame
    /// as Reference.
    private let freezeMenuButton = NSButton()
    /// The ▾ beside the pointer toggle: Crosshair, Cursor or Original Cursor in the Capture.
    private let pointerMenuButton = NSButton()
    private let selectButton = NSButton()
    private let selectMenuItem = NSMenuItem(title: "Select", action: nil, keyEquivalent: "")
    private let rulerButton = NSButton()
    /// The ▾ beside the ruler button: Corner Ruler or Selection Ruler.
    private let rulerMenuButton = NSButton()
    private let rulerMenuItem = NSMenuItem(title: "Ruler", action: nil, keyEquivalent: "")
    private let visionButton = NSButton()
    /// The ▾ beside the eye button: the colour vision modes.
    private let visionMenuButton = NSButton()
    private let visionMenuItem = NSMenuItem(title: "Color Vision", action: nil, keyEquivalent: "")
    private let freezeMenuItem = NSMenuItem(title: "Freeze Frame", action: nil, keyEquivalent: "")
    private let onTopButton = NSButton()
    private let copyButton = NSButton()
    /// The ▾ beside Copy: Copy View or Copy Source.
    private let copyMenuButton = NSButton()
    private let saveButton = NSButton()
    /// The ▾ beside Save: Save View… or Save Source….
    private let saveMenuButton = NSButton()

    /// The overflow-menu forms.
    private let onTopMenuItem = NSMenuItem(title: "Keep on Top", action: nil, keyEquivalent: "")

    private let settings: SettingsStore
    private let ruler: RulerController
    private let selection: SelectionController
    private let colorVision: ColorVisionController
    /// Frozen or counting down to a freeze, as `setFrozen` last reported it.
    private var isFrozen = false
    let toolbar = NSToolbar(identifier: "Viewer")

    init(
        settings: SettingsStore, ruler: RulerController, selection: SelectionController,
        colorVision: ColorVisionController
    ) {
        self.settings = settings
        self.ruler = ruler
        self.selection = selection
        self.colorVision = colorVision
        super.init()
        configure(copyButton, symbol: "doc.on.doc", title: "Copy View (⌘C)", action: #selector(copyClicked(_:)))
        configure(
            copyMenuButton, symbol: "chevron.down", title: "Copy View or Source", action: #selector(copyMenuClicked(_:))
        )
        configure(
            saveButton, symbol: "square.and.arrow.down", title: "Save View… (⌘S)", action: #selector(saveClicked(_:)))
        configure(
            saveMenuButton, symbol: "chevron.down", title: "Save View or Source", action: #selector(saveMenuClicked(_:))
        )
        for button in [copyMenuButton, saveMenuButton] {
            button.image = button.image?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 8, weight: .semibold))
            button.widthAnchor.constraint(equalToConstant: 16).isActive = true
        }
        configure(zoomButton, symbol: "plus.magnifyingglass", title: "Zoom Panel", action: #selector(zoomClicked(_:)))
        zoomButton.setButtonType(.pushOnPushOff)
        configure(
            zoomMenuButton, symbol: "chevron.down", title: "Zoom Presets and Panel Style",
            action: #selector(zoomMenuClicked(_:)))
        zoomMenuButton.image = zoomMenuButton.image?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 8, weight: .semibold))
        zoomMenuButton.widthAnchor.constraint(equalToConstant: 16).isActive = true
        zoomMenuItem.submenu = MainMenu.zoomMenu(withToggle: true, target: nil)
        configure(onTopButton, symbol: "pin", title: "Keep on Top", action: #selector(onTopClicked(_:)))
        onTopButton.setButtonType(.pushOnPushOff)
        configure(freezeButton, symbol: "pause", title: "Freeze Frame (Space)", action: #selector(freezeClicked(_:)))
        // Lucide's pause, two outlined bars: SF Symbols has only solid ones.
        freezeButton.image = NSImage(named: "pause")
        freezeButton.image?.accessibilityDescription = "Freeze Frame (Space)"
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
        configure(rulerButton, symbol: "ruler", title: "Corner Ruler (⌘R)", action: #selector(rulerClicked(_:)))
        rulerButton.setButtonType(.pushOnPushOff)
        configure(
            rulerMenuButton, symbol: "chevron.down", title: "Corner or Selection Ruler",
            action: #selector(rulerMenuClicked(_:)))
        rulerMenuButton.image = rulerMenuButton.image?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 8, weight: .semibold))
        rulerMenuButton.widthAnchor.constraint(equalToConstant: 16).isActive = true
        // The View menu's commands, which also check the ruler that is on.
        let rulerMenu = NSMenu()
        rulerMenu.addItem(
            withTitle: "Corner Ruler", action: #selector(AppController.toggleCornerRuler(_:)), keyEquivalent: "")
        rulerMenu.addItem(
            withTitle: "Selection Ruler", action: #selector(AppController.toggleSelectionRuler(_:)), keyEquivalent: "")
        rulerMenuItem.submenu = rulerMenu
        configure(
            visionButton, symbol: "eye", title: "Simulate Color Vision (⌘Y)", action: #selector(visionClicked(_:)))
        visionButton.setButtonType(.pushOnPushOff)
        configure(
            visionMenuButton, symbol: "chevron.down", title: "Color Vision", action: #selector(visionMenuClicked(_:)))
        visionMenuButton.image = visionMenuButton.image?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 8, weight: .semibold))
        visionMenuButton.widthAnchor.constraint(equalToConstant: 16).isActive = true
        visionMenuItem.submenu = MainMenu.colorVisionMenu(withToggle: true, target: nil)
        for (index, toggle) in Toggle.allCases.enumerated() {
            if !Toggle.panels.contains(toggle) {
                let button = NSButton()
                configure(button, symbol: toggle.symbol, title: toggle.title, action: #selector(toggleClicked(_:)))
                button.setButtonType(.pushOnPushOff)
                button.tag = index
                toggleButtons[toggle] = button
            }
            let item = NSMenuItem(title: toggle.title, action: #selector(toggleClicked(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            toggleMenuItems[toggle] = item
        }
        panels.target = self
        panels.setAccessibilityLabel("Panels")
        panels.action = #selector(panelClicked(_:))
        let panelsMenu = NSMenu()
        for (index, toggle) in Toggle.panels.enumerated() {
            panels.setToolTip(toggle.title, forSegment: index)
            if let item = toggleMenuItems[toggle] { panelsMenu.addItem(item) }
        }
        panelsMenuItem.submenu = panelsMenu
        onTopButton.alternateImage = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Keep on Top")

        onTopMenuItem.action = #selector(AppController.toggleViewerAlwaysOnTop(_:))

        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        ruler.observe { [weak self] in self?.showRuler() }
        showRuler()
        selection.observe { [weak self] in self?.showSelectTool() }
        showSelectTool()
        colorVision.observe { [weak self] in self?.showColorVision() }
        showColorVision()
        settings.observe(\.viewerAlwaysOnTop) { [weak self] in self?.show($0, on: self?.onTopButton) }
        settings.observe(\.zoomPanelVisible) { [weak self] in self?.show($0, on: self?.zoomButton) }
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

    private func show(_ isOn: Bool, on button: NSButton?) {
        button?.state = isOn ? .on : .off
    }

    private func showToggle(_ toggle: Toggle, isOn: Bool) {
        show(isOn, on: toggleButtons[toggle])
        if let index = Toggle.panels.firstIndex(of: toggle) {
            panels.setSelected(isOn, forSegment: index)
        }
        toggleMenuItems[toggle]?.state = isOn ? .on : .off
    }

    /// The button's name follows the chosen mode.
    private func showRuler() {
        show(ruler.isOn, on: rulerButton)
        let title = ruler.mode == .corner ? "Corner Ruler (⌘R)" : "Selection Ruler (⌥⌘R)"
        rulerButton.toolTip = title
        rulerButton.setAccessibilityLabel(title)
    }

    private func showSelectTool() {
        show(selection.isToolOn, on: selectButton)
    }

    /// The eye button's name follows the chosen mode.
    private func showColorVision() {
        show(colorVision.isOn, on: visionButton)
        let title = "Simulate \(colorVision.mode.title) (⌘Y)"
        visionButton.toolTip = title
        visionButton.setAccessibilityLabel(title)
    }

    /// Freeze Now, the delays and Use Frozen Frame as Reference, as `AppController` commands, which
    /// also enable them; the overflow form starts with the Freeze toggle itself.
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
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Use Frozen Frame as Reference", action: #selector(AppController.useFrozenFrameAsReference(_:)),
            keyEquivalent: "")
        return menu
    }

    func setFrozen(_ isOn: Bool) {
        isFrozen = isOn
        show(isOn, on: freezeButton)
    }

    /// While a recent capture shows, Freeze and the pointer have nothing to act on.
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
        apply(Toggle.allCases[tag])
    }

    /// A clicked segment flips itself, so it is the one that differs from its panel's state. It goes
    /// back to that state before the panel toggles, and the settings then report the new state of
    /// every panel.
    @objc private func panelClicked(_ sender: NSSegmentedControl) {
        let current = settings.settings
        // In the order of `Toggle.panels`.
        let isOn = [current.meterVisible, current.referencesVisible, current.capturesVisible]
        let shown = isOn.indices.map { sender.isSelected(forSegment: $0) }
        guard let index = ToolbarSelection.clicked(shown: shown, model: isOn) else { return }
        sender.setSelected(isOn[index], forSegment: index)
        apply(Toggle.panels[index])
    }

    private func apply(_ toggle: Toggle) {
        settings.update {
            switch toggle {
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

    @objc private func zoomClicked(_ sender: NSButton) {
        send(#selector(AppController.toggleZoomPanel(_:)), from: sender, isOn: settings.settings.zoomPanelVisible)
    }

    /// The presets, the current one checked, and the panel's styles, the chosen one checked.
    @objc private func zoomMenuClicked(_ sender: NSButton) {
        let below = NSPoint(x: -zoomButton.frame.width, y: sender.isFlipped ? sender.bounds.maxY + 4 : -4)
        MainMenu.zoomMenu(withToggle: false, target: nil).popUp(positioning: nil, at: below, in: sender)
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

    /// The two rulers, the chosen one checked, whether it is on or not.
    @objc private func rulerMenuClicked(_ sender: NSButton) {
        let menu = NSMenu()
        for (index, mode) in RulerMode.allCases.enumerated() {
            let item = menu.addItem(
                withTitle: mode == .corner ? "Corner Ruler" : "Selection Ruler", action: #selector(rulerModeChosen(_:)),
                keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = mode == ruler.mode ? .on : .off
        }
        let below = NSPoint(x: -rulerButton.frame.width, y: sender.isFlipped ? sender.bounds.maxY + 4 : -4)
        menu.popUp(positioning: nil, at: below, in: sender)
    }

    /// Choosing a ruler also turns it on.
    @objc private func rulerModeChosen(_ sender: NSMenuItem) {
        ruler.turnOn(RulerMode.allCases[sender.tag])
    }

    @objc private func visionClicked(_ sender: NSButton) {
        send(#selector(AppController.toggleColorVision(_:)), from: sender, isOn: colorVision.isOn)
    }

    /// The modes, the chosen one checked, whether it is on or not; choosing one turns it on.
    @objc private func visionMenuClicked(_ sender: NSButton) {
        let below = NSPoint(x: -visionButton.frame.width, y: sender.isFlipped ? sender.bounds.maxY + 4 : -4)
        MainMenu.colorVisionMenu(withToggle: false, target: nil).popUp(positioning: nil, at: below, in: sender)
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

    /// Copy View and Copy Source, as `AppController` commands, which also enable them, with their
    /// shortcuts.
    @objc private func copyMenuClicked(_ sender: NSButton) {
        popUp(
            [
                ("Copy View", #selector(AppController.copyView(_:)), "c"),
                ("Copy Source", #selector(AppController.copySource(_:)), "C"),
            ], below: sender, beside: copyButton)
    }

    /// Save View… and Save Source…, as Copy's ▾.
    @objc private func saveMenuClicked(_ sender: NSButton) {
        popUp(
            [
                ("Save View…", #selector(AppController.saveView(_:)), "s"),
                ("Save Source…", #selector(AppController.saveSource(_:)), "S"),
            ], below: sender, beside: saveButton)
    }

    /// A ▾'s menu of commands, under the button it belongs to. The shortcuts show only here: the
    /// overflow forms show none, as the toolbar's other menu forms, so no item outside the main menu
    /// holds them.
    private func popUp(_ commands: [(String, Selector, String)], below sender: NSButton, beside button: NSButton) {
        let menu = NSMenu()
        for (title, action, key) in commands {
            menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        let below = NSPoint(x: -button.frame.width, y: sender.isFlipped ? sender.bounds.maxY + 4 : -4)
        menu.popUp(positioning: nil, at: below, in: sender)
    }

    // MARK: NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .flexibleSpace, Self.zoomID, Self.freezeID, Self.selectID, Self.rulerID, Self.gridID, Self.crosshairID,
            Self.visionID, Self.panelsID, .space, Self.copyID, Self.saveID, Self.onTopID,
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
        case Self.zoomID:
            let group = NSStackView(views: [zoomButton, zoomMenuButton])
            group.spacing = 0
            item.view = group
            item.label = "Zoom"
            item.menuFormRepresentation = zoomMenuItem
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
            let group = NSStackView(views: [rulerButton, rulerMenuButton])
            group.spacing = 0
            item.view = group
            item.label = "Ruler"
            item.menuFormRepresentation = rulerMenuItem
        case Self.visionID:
            let group = NSStackView(views: [visionButton, visionMenuButton])
            group.spacing = 0
            item.view = group
            item.label = "Color Vision"
            item.menuFormRepresentation = visionMenuItem
        case Self.crosshairID:
            let group = NSStackView(views: [toggleButtons[.crosshair], pointerMenuButton].compactMap { $0 })
            group.spacing = 0
            item.view = group
            item.label = "Pointer"
            item.menuFormRepresentation = toggleMenuItems[.crosshair]
        case Self.gridID:
            item.view = toggleButtons[.grid]
            item.label = Toggle.grid.title
            item.menuFormRepresentation = toggleMenuItems[.grid]
        case Self.panelsID:
            item.view = panels
            item.label = "Panels"
            item.menuFormRepresentation = panelsMenuItem
        case Self.copyID:
            let group = NSStackView(views: [copyButton, copyMenuButton])
            group.spacing = 0
            item.view = group
            item.label = "Copy View"
            // An `AppController` command, which also enables it.
            item.menuFormRepresentation = NSMenuItem(
                title: "Copy View", action: #selector(AppController.copyView(_:)), keyEquivalent: "")
        case Self.saveID:
            let group = NSStackView(views: [saveButton, saveMenuButton])
            group.spacing = 0
            item.view = group
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
