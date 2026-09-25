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

    @objc func toggleCaptureArea(_ sender: Any?) {
        windows.toggleCaptureArea()
    }

    @objc func pickWindowForCaptureArea(_ sender: Any?) {
        windows.pickWindow()
    }

    @objc func toggleViewerAlwaysOnTop(_ sender: Any?) {
        windows.viewer.toggleAlwaysOnTop()
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
        case #selector(toggleViewerAlwaysOnTop(_:)):
            menuItem.state = settings.settings.viewerAlwaysOnTop ? .on : .off
            return true
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
    /// Edit › Copy copies the text of a focused text field, and the view otherwise; its title says which.
    func menuNeedsUpdate(_ menu: NSMenu) {
        let editsText = NSApp.keyWindow?.firstResponder is NSText
        menu.items.first { $0.action == #selector(NSText.copy(_:)) }?.title = editsText ? "Copy" : "Copy View"
    }
}
