import AppKit

/// Wires the app together and handles the app's commands. It is the app delegate, so it ends the
/// responder chain: a command sent with no target (the Viewer's toolbar, Space in the Viewer, ⌘C)
/// reaches it from any window, and the menus validate against it.
@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private let permissions = PermissionsManager()
    private var builtWindows: WindowManager?
    /// Built on first use. With nothing shown at launch, the windows, Metal and the capture wait
    /// until something needs them; code that only reacts to them uses `builtWindows`.
    private var windows: WindowManager {
        if let builtWindows { return builtWindows }
        let windows = WindowManager(settings: settings, permissions: permissions)
        builtWindows = windows
        return windows
    }
    private let shortcuts = GlobalShortcuts()
    /// Built the first time Settings opens, then kept.
    private var settingsWindow: SettingsWindowController?
    /// Built the first time Help › Acknowledgements opens, then kept.
    private var acknowledgementsWindow: AcknowledgementsWindowController?
    private var statusItem: StatusItemController?
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // One copy at a time: two would fight over the global shortcuts and the settings. A second
        // launch — another build of the app, `open -n` — hands over to the running one and quits.
        // Opening the running app's bundle reopens it, which brings its Viewer forward.
        if let running = NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? ""
        ).first(where: { $0 != .current }), let url = running.bundleURL {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
            return
        }
        settings.observe(\.showsDockIcon) { [weak self] in self?.applyDockIcon($0) }
        NSApp.mainMenu = MainMenu.make(target: self)
        statusItem = StatusItemController(target: self)
        shortcuts.onAction = { [weak self] action in self?.perform(action) }
        settings.observe(\.shortcuts) { [weak self] in self?.shortcuts.register($0) }
        settings.observe(\.viewerAlwaysOnTop) { [weak self] _ in
            guard let self else { return }
            settingsWindow?.window?.level = settingsLevel
            acknowledgementsWindow?.window?.level = settingsLevel
        }
        // Without Screen Recording access the Viewer explains why it is needed and asks from there,
        // even when Settings says to show nothing on launch.
        if settings.settings.showsWindowsOnLaunch || !permissions.hasScreenRecordingAccess {
            windows.showViewer()
        }

        let center = NotificationCenter.default
        observers.append(
            center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main)
            {
                [weak self] _ in
                MainActor.assumeIsolated { self?.builtWindows?.displaysChanged() }
            })
        observers.append(
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated { self?.builtWindows?.viewer.refreshContent() }
            })
    }

    /// Saves what AppKit doesn't keep by itself before the app quits.
    func applicationWillTerminate(_ notification: Notification) {
        // The live view's zoom is the one kept, not a recent capture's.
        builtWindows?.viewer.showLive()
        builtWindows?.saveViewerState()
        builtWindows?.saveProject()
    }

    /// Closing the Viewer keeps the app running in the menu bar (docs/product.md, Menu bar and app mode).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windows.showViewer()
        return true
    }

    // MARK: Commands

    @objc func showViewer(_ sender: Any?) {
        windows.showViewer()
    }

    @objc func openImage(_ sender: Any?) {
        windows.openImage()
    }

    @objc func toggleCaptureArea(_ sender: Any?) {
        windows.toggleCaptureArea()
    }

    @objc func pickWindowForCaptureArea(_ sender: Any?) {
        windows.pickWindow()
    }

    /// View › Show Viewport Handle and the global shortcut; the Capture Area's viewport button turns
    /// the same setting.
    @objc func toggleViewportHandle(_ sender: Any?) {
        settings.update { $0.showsViewportHandle.toggle() }
    }

    @objc func toggleViewerAlwaysOnTop(_ sender: Any?) {
        windows.viewer.toggleAlwaysOnTop()
    }

    @objc func toggleScreenshotStudio(_ sender: Any?) {
        windows.studio.toggle()
    }

    @objc func toggleStudioOnTop(_ sender: Any?) {
        windows.studio.toggleKeepOnTop()
    }

    @objc func captureStudio(_ sender: Any?) {
        windows.studio.capture()
    }

    @objc func copyStudio(_ sender: Any?) {
        windows.studio.copy()
    }

    @objc func saveStudio(_ sender: Any?) {
        windows.studio.save()
    }

    /// Screenshot › Size: the item carries `[width, height]` in pixels.
    @objc func applyStudioSize(_ sender: NSMenuItem) {
        guard let size = sender.representedObject as? [Int], size.count == 2 else { return }
        windows.studio.applySize(PixelSize(width: size[0], height: size[1]))
    }

    @objc func showStudioCustomSizes(_ sender: Any?) {
        windows.studio.showCustomSizes()
    }

    @objc func toggleStudioAspectLock(_ sender: Any?) {
        windows.studio.toggleAspectLock()
    }

    /// Screenshot › Delay: the item's tag is the delay in seconds.
    @objc func chooseStudioDelay(_ sender: NSMenuItem) {
        guard let delay = StudioDelay(rawValue: sender.tag) else { return }
        windows.studio.chooseDelay(delay)
    }

    /// Screenshot › Output: each item carries its choice.
    @objc func chooseStudioFormat(_ sender: NSMenuItem) {
        guard let format = sender.representedObject as? StudioOutput.Format else { return }
        settings.update { $0.studioOutput.format = format }
    }

    @objc func chooseStudioColors(_ sender: NSMenuItem) {
        guard let colors = sender.representedObject as? StudioOutput.Colors else { return }
        settings.update { $0.studioOutput.colors = colors }
    }

    @objc func chooseStudioScale(_ sender: NSMenuItem) {
        guard let scale = sender.representedObject as? StudioOutput.Scale else { return }
        settings.update { $0.studioOutput.scale = scale }
    }

    @objc func toggleStudioPointer(_ sender: Any?) {
        windows.studio.togglePointer()
    }

    /// Screenshot › Background: the item carries its `StudioBackground`.
    @objc func chooseStudioBackground(_ sender: NSMenuItem) {
        guard let background = sender.representedObject as? StudioBackground else { return }
        windows.studio.chooseBackground(background)
    }

    @objc func chooseStudioCustomColor(_ sender: Any?) {
        windows.studio.chooseCustomColor()
    }

    @objc func chooseStudioBackgroundImage(_ sender: Any?) {
        windows.studio.chooseBackgroundImage()
    }

    @objc func toggleStudioLeaveOutWindows(_ sender: Any?) {
        windows.studio.toggleLeavingOutWindows()
    }

    @objc func bringBackStudioWindows(_ sender: Any?) {
        windows.studio.bringBackAllWindows()
    }

    @objc func toggleStudioOneWindow(_ sender: Any?) {
        windows.studio.toggleOneWindow()
    }

    @objc func toggleStudioWindowShadow(_ sender: Any?) {
        windows.studio.toggleWindowShadow()
    }

    @objc func toggleStudioLeaveOutDock(_ sender: Any?) {
        windows.studio.toggleLeaveOutDock()
    }

    @objc func toggleStudioLeaveOutDesktopIcons(_ sender: Any?) {
        windows.studio.toggleLeaveOutDesktopIcons()
    }

    @objc func resetZoom(_ sender: Any?) {
        windows.resetZoom()
    }

    /// Not `toggleRuler(_:)`: that is an `NSText` action, which a text field being edited would take.
    @objc func toggleMeasuringRuler(_ sender: Any?) {
        windows.viewer.toggleRuler()
    }

    @objc func toggleFreeze(_ sender: Any?) {
        windows.toggleFreeze()
    }

    @objc func freezeNow(_ sender: Any?) {
        windows.freezeNow()
    }

    /// Freeze in 3, 5 or 10 seconds: the menu item's tag.
    @objc func freezeAfterDelay(_ sender: Any?) {
        guard let seconds = (sender as? NSMenuItem)?.tag, seconds > 0 else { return }
        windows.freeze(after: seconds)
    }

    /// Escape in the Viewer.
    @objc func cancelFreezeCountdown(_ sender: Any?) {
        builtWindows?.cancelFreezeCountdown()
    }

    @objc func toggleSelectTool(_ sender: Any?) {
        windows.viewer.toggleSelectTool()
    }

    /// Edit › Select All (⌘A) when no text field has the focus: the Select tool takes the whole
    /// Capture Area.
    @objc func selectAll(_ sender: Any?) {
        windows.viewer.selectWholeArea()
    }

    @objc func sizeViewerToArea(_ sender: Any?) {
        windows.viewer.sizeToArea()
    }

    @objc func copyView(_ sender: Any?) {
        windows.export.copyView()
    }

    /// Edit › Copy View (⌘C) when no text field has the focus: a text field with the focus copies its
    /// text first.
    @objc func copy(_ sender: Any?) {
        windows.export.copyView()
    }

    @objc func copySource(_ sender: Any?) {
        windows.export.copySource()
    }

    @objc func saveView(_ sender: Any?) {
        windows.export.saveView()
    }

    @objc func saveSource(_ sender: Any?) {
        windows.export.saveSource()
    }

    #if DEBUG
        @objc func simulateInterruptionThatRecovers(_ sender: Any?) {
            windows.simulateCaptureInterruption(recovers: true)
        }

        @objc func simulateInterruptionThatFails(_ sender: Any?) {
            windows.simulateCaptureInterruption(recovers: false)
        }
    #endif

    /// The guide on the project's website (docs/guide.md).
    private static let guide = "https://ayenora.github.io/screen-loupe/guide"

    @objc func showGuide(_ sender: Any?) {
        NSWorkspace.shared.open(URL(string: Self.guide)!)
    }

    @objc func showKeyboardShortcuts(_ sender: Any?) {
        NSWorkspace.shared.open(URL(string: Self.guide + "#keyboard-shortcuts")!)
    }

    @objc func showAcknowledgements(_ sender: Any?) {
        let controller = acknowledgementsWindow ?? AcknowledgementsWindowController()
        acknowledgementsWindow = controller
        controller.show(above: settingsLevel)
    }

    @objc func showSettings(_ sender: Any?) {
        let controller = settingsWindow ?? SettingsWindowController(settings: settings, shortcuts: shortcuts)
        settingsWindow = controller
        controller.show(above: settingsLevel)
    }

    /// Settings stays above the Viewer when the Viewer is kept on top.
    private var settingsLevel: NSWindow.Level { settings.settings.viewerAlwaysOnTop ? .floating : .normal }

    /// Menu bar only: no Dock icon and no main menu bar. Switching keeps the app active, so an open
    /// Settings window stays in front.
    private func applyDockIcon(_ showsDockIcon: Bool) {
        NSApp.setActivationPolicy(showsDockIcon ? .regular : .accessory)
        if NSApp.isActive || settingsWindow?.window?.isVisible == true {
            NSApp.activate()
        }
    }

    private func perform(_ action: ShortcutAction) {
        switch action {
        case .toggleCaptureArea: windows.toggleCaptureArea()
        case .toggleViewer: windows.toggleViewer()
        case .copyView: windows.export.copyView()
        case .copySource: windows.export.copySource()
        case .toggleFreeze: windows.toggleFreeze(hint: frozenFromAnotherAppHint())
        case .pickWindow: windows.pickWindow()
        case .toggleViewportHandle: toggleViewportHandle(nil)
        }
    }

    /// "Frozen by F13 from Simulator — let go of the mouse, then zoom, pan, copy", when the global
    /// Freeze shortcut is pressed while another app is in front: the mouse may be held down there.
    private func frozenFromAnotherAppHint() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication,
            app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return nil }
        let key = settings.settings.shortcuts.toggleFreeze.map { " by \($0.displayString)" } ?? ""
        let from = app.localizedName.map { " from \($0)" } ?? ""
        return "Frozen\(key)\(from) — let go of the mouse, then zoom, pan, copy"
    }
}

extension AppController: NSMenuItemValidation {
    /// Reads the windows only when they exist: opening a menu doesn't build them.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let canExport = builtWindows?.export.canExport == true
        switch menuItem.action {
        case #selector(toggleCaptureArea(_:)):
            let isVisible = builtWindows?.captureArea.isVisible == true
            menuItem.title = isVisible ? "Hide Capture Area" : "Show Capture Area"
            return true
        case #selector(toggleViewportHandle(_:)):
            menuItem.state = settings.settings.showsViewportHandle ? .on : .off
            return true
        case #selector(toggleViewerAlwaysOnTop(_:)):
            menuItem.state = settings.settings.viewerAlwaysOnTop ? .on : .off
            return true
        case #selector(toggleScreenshotStudio(_:)):
            let isVisible = builtWindows?.studio.isVisible == true
            menuItem.title = isVisible ? "Hide Screenshot Studio" : "Show Screenshot Studio"
            return true
        case #selector(toggleStudioOnTop(_:)):
            menuItem.state = settings.settings.studioOnTop ? .on : .off
            return true
        case #selector(captureStudio(_:)), #selector(copyStudio(_:)), #selector(saveStudio(_:)):
            return builtWindows?.studio.isVisible == true
        case #selector(applyStudioSize(_:)):
            let checked = (menuItem.representedObject as? [Int]).map {
                StudioSizes.isChecked(
                    PixelSize(width: $0[0], height: $0[1]), isPresetEntry: menuItem.tag == 0,
                    current: builtWindows?.studio.pixelSize)
            }
            menuItem.state = checked == true ? .on : .off
            return builtWindows?.studio.isVisible == true
        case #selector(toggleStudioAspectLock(_:)):
            menuItem.state = settings.settings.studioAspectLocked ? .on : .off
            return true
        case #selector(chooseStudioDelay(_:)):
            menuItem.state = menuItem.tag == settings.settings.studioDelay.rawValue ? .on : .off
            return true
        case #selector(chooseStudioFormat(_:)):
            let format = menuItem.representedObject as? StudioOutput.Format
            menuItem.state = format == settings.settings.studioOutput.format ? .on : .off
            return true
        case #selector(chooseStudioColors(_:)):
            let colors = menuItem.representedObject as? StudioOutput.Colors
            menuItem.state = colors == settings.settings.studioOutput.colors ? .on : .off
            return true
        case #selector(chooseStudioScale(_:)):
            let scale = menuItem.representedObject as? StudioOutput.Scale
            menuItem.state = scale == settings.settings.studioOutput.scale ? .on : .off
            return true
        case #selector(toggleStudioPointer(_:)):
            menuItem.state = settings.settings.studioIncludesPointer ? .on : .off
            return true
        case #selector(chooseStudioBackground(_:)):
            let background = menuItem.representedObject as? StudioBackground
            menuItem.state = background == settings.settings.studioBackground ? .on : .off
            return true
        case #selector(chooseStudioCustomColor(_:)):
            menuItem.state = settings.settings.studioBackground.isCustomColor ? .on : .off
            return true
        case #selector(chooseStudioBackgroundImage(_:)):
            if case .image(let image) = settings.settings.studioBackground {
                menuItem.state = .on
                menuItem.title = "Image… · \(image.name)"
            } else {
                menuItem.state = .off
                menuItem.title = "Image…"
            }
            return true
        case #selector(toggleStudioLeaveOutWindows(_:)):
            menuItem.state = builtWindows?.studio.isLeavingOutWindows == true ? .on : .off
            return builtWindows?.studio.isVisible == true
        case #selector(bringBackStudioWindows(_:)):
            return builtWindows?.studio.hasLeftOutWindows == true
        case #selector(toggleStudioOneWindow(_:)):
            // Checked while the window is picked; a chosen window can be let go also while the
            // studio is hidden.
            let mode = builtWindows?.studio.oneWindowMode ?? .off
            menuItem.title = mode.chosen == nil ? "Capture One Window…" : "Stop One Window"
            menuItem.state = mode.isPicking ? .on : .off
            return mode.chosen != nil || builtWindows?.studio.isVisible == true
        case #selector(toggleStudioWindowShadow(_:)):
            menuItem.state = settings.settings.studioWindowShadow ? .on : .off
            return true
        case #selector(toggleStudioLeaveOutDock(_:)):
            menuItem.state = settings.settings.studioLeavesOutDock ? .on : .off
            return true
        case #selector(toggleStudioLeaveOutDesktopIcons(_:)):
            // A background other than the screen leaves them out anyway.
            let current = settings.settings
            let leaveOut = StudioLeaveOut(
                dock: current.studioLeavesOutDock, desktopIcons: current.studioLeavesOutDesktopIcons,
                background: current.studioBackground, windows: [])
            menuItem.state = leaveOut.desktopIcons ? .on : .off
            return !leaveOut.wallpaper
        case #selector(toggleMeasuringRuler(_:)):
            menuItem.state = builtWindows?.viewer.isRulerOn == true ? .on : .off
            return builtWindows?.viewer.showsCapture == true
        case #selector(toggleFreeze(_:)):
            let isFrozen = builtWindows?.isFrozen == true
            let isCounting = builtWindows?.isFreezeCountingDown == true
            menuItem.state = isFrozen || isCounting ? .on : .off
            // A recent capture in the Viewer is still anyway (docs/product.md, Recent Captures).
            guard builtWindows?.viewer.isShowingCapture != true else { return false }
            return isFrozen || isCounting || canExport
        case #selector(freezeNow(_:)), #selector(freezeAfterDelay(_:)):
            guard builtWindows?.viewer.isShowingCapture != true else { return false }
            return builtWindows?.isFrozen == true || canExport
        case #selector(NSText.selectAll(_:)):
            return builtWindows?.viewer.showsCapture == true
        case #selector(toggleSelectTool(_:)):
            menuItem.state = builtWindows?.viewer.isSelectToolOn == true ? .on : .off
            return builtWindows?.viewer.showsCapture == true
        case #selector(openImage(_:)):
            return builtWindows?.isChoosingImage != true
        case #selector(sizeViewerToArea(_:)):
            return builtWindows?.viewer.canSizeToArea == true
        case #selector(copyView(_:)), #selector(NSText.copy(_:)), #selector(copySource(_:)), #selector(saveView(_:)),
            #selector(saveSource(_:)):
            return canExport
        default:
            return true
        }
    }
}

extension AppController: NSMenuDelegate {
    /// Screenshot › Size is filled as it opens. Edit › Copy copies the text of a focused text field,
    /// and the view otherwise; its title says which.
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu.identifier == MainMenu.studioSizeMenu {
            MainMenu.fillStudioSizeMenu(menu, custom: settings.settings.studioCustomSizes, target: self)
            return
        }
        let editsText = NSApp.keyWindow?.firstResponder is NSText
        menu.items.first { $0.action == #selector(NSText.copy(_:)) }?.title = editsText ? "Copy" : "Copy View"
    }
}
