import AppKit

/// Wires the app together and handles the commands shared by the main menu and the menu bar item.
@MainActor
final class AppController: NSObject {
    private let settings = SettingsStore()
    private let permissions = PermissionsManager()
    private lazy var windows = WindowManager(settings: settings, permissions: permissions)
    private var statusItem: StatusItemController?
    private var observers: [NSObjectProtocol] = []

    func start() {
        NSApp.mainMenu = MainMenu.make(target: self)
        statusItem = StatusItemController(target: self)
        // Without Screen Recording access the Viewer explains why it is needed and asks from there.
        windows.showViewer()

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

    // Implemented in stages 6–7 and after the MVP (docs/design.md §7); disabled until then.
    @objc func copyView(_ sender: Any?) {}
    @objc func copySource(_ sender: Any?) {}
    @objc func resetZoom(_ sender: Any?) {}
    @objc func showPreferences(_ sender: Any?) {}
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
        case #selector(copyView(_:)), #selector(copySource(_:)), #selector(resetZoom(_:)),
            #selector(showPreferences(_:)):
            return false
        default:
            return true
        }
    }
}
