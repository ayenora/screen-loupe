import AppKit

/// Wires the app together and handles the commands shared by the main menu and the menu bar item.
@MainActor
final class AppController: NSObject {
    private let settings = SettingsStore()
    private let permissions = PermissionsManager()
    private lazy var windows = WindowManager(settings: settings, permissions: permissions)
    private let shortcuts = GlobalShortcuts()
    /// Built the first time Settings opens, then kept.
    private var settingsWindow: SettingsWindowController?
    private var statusItem: StatusItemController?
    private var observers: [NSObjectProtocol] = []

    func start() {
        applyDockIcon()
        NSApp.mainMenu = MainMenu.make(target: self)
        statusItem = StatusItemController(target: self)
        shortcuts.onAction = { [weak self] action in self?.perform(action) }
        shortcuts.register(settings.settings.shortcuts)
        settings.observe { [weak self] old, new in
            if old.shortcuts != new.shortcuts { self?.shortcuts.register(new.shortcuts) }
            if old.showsDockIcon != new.showsDockIcon { self?.applyDockIcon() }
            if old.viewerAlwaysOnTop != new.viewerAlwaysOnTop, let self {
                self.settingsWindow?.window?.level = self.settingsLevel
            }
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
                MainActor.assumeIsolated { self?.windows.displaysChanged() }
            })
        observers.append(
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated { self?.windows.viewer.refreshContent() }
            })
    }

    func reopen() {
        windows.showViewer()
    }

    // MARK: Commands

    @objc func showViewer(_ sender: Any?) {
        windows.showViewer()
    }

    @objc func toggleCaptureArea(_ sender: Any?) {
        windows.toggleCaptureArea()
    }

    @objc func toggleViewerAlwaysOnTop(_ sender: Any?) {
        windows.viewer.toggleAlwaysOnTop()
    }

    @objc func resetZoom(_ sender: Any?) {
        windows.resetZoom()
    }

    @objc func toggleRuler(_ sender: Any?) {
        windows.viewer.toggleRuler()
    }

    @objc func toggleFreeze(_ sender: Any?) {
        windows.toggleFreeze()
    }

    @objc func sizeViewerToArea(_ sender: Any?) {
        windows.viewer.sizeToArea()
    }

    /// Saves what AppKit doesn't keep by itself before the app quits.
    func willTerminate() {
        windows.saveViewerState()
        windows.saveProject()
    }

    @objc func copyView(_ sender: Any?) {
        windows.copyView()
    }

    @objc func copySource(_ sender: Any?) {
        windows.copySource()
    }

    @objc func saveView(_ sender: Any?) {
        windows.saveView()
    }

    @objc func saveSource(_ sender: Any?) {
        windows.saveSource()
    }

    #if DEBUG
        @objc func simulateInterruptionThatRecovers(_ sender: Any?) {
            windows.simulateCaptureInterruption(recovers: true)
        }

        @objc func simulateInterruptionThatFails(_ sender: Any?) {
            windows.simulateCaptureInterruption(recovers: false)
        }
    #endif

    @objc func showSettings(_ sender: Any?) {
        let controller = settingsWindow ?? SettingsWindowController(settings: settings, shortcuts: shortcuts)
        settingsWindow = controller
        controller.show(above: settingsLevel)
    }

    /// Settings stays above the Viewer when the Viewer is kept on top.
    private var settingsLevel: NSWindow.Level { windows.viewer.isAlwaysOnTop ? .floating : .normal }

    /// Menu bar only: no Dock icon and no main menu bar. Switching keeps the app active, so an open
    /// Settings window stays in front.
    private func applyDockIcon() {
        NSApp.setActivationPolicy(settings.settings.showsDockIcon ? .regular : .accessory)
        if NSApp.isActive || settingsWindow?.window?.isVisible == true {
            NSApp.activate()
        }
    }

    private func perform(_ action: ShortcutAction) {
        switch action {
        case .toggleCaptureArea: windows.toggleCaptureArea()
        case .toggleViewer: windows.toggleViewer()
        case .copyView: windows.copyView()
        case .copySource: windows.copySource()
        }
    }
}

extension AppController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleCaptureArea(_:)):
            menuItem.title = windows.captureArea.isVisible ? "Hide Capture Area" : "Show Capture Area"
            return true
        case #selector(toggleViewerAlwaysOnTop(_:)):
            menuItem.state = windows.viewer.isAlwaysOnTop ? .on : .off
            return true
        case #selector(toggleRuler(_:)):
            menuItem.state = windows.viewer.isRulerOn ? .on : .off
            return windows.viewer.showsCapture
        case #selector(toggleFreeze(_:)):
            menuItem.state = windows.isFrozen ? .on : .off
            return windows.isFrozen || windows.canExport
        case #selector(sizeViewerToArea(_:)):
            return windows.viewer.canSizeToArea
        case #selector(copyView(_:)), #selector(NSText.copy(_:)), #selector(copySource(_:)), #selector(saveView(_:)),
            #selector(saveSource(_:)):
            return windows.canExport
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
