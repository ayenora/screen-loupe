import AppKit

/// Owns the two independent windows: the Capture Area overlay and the Viewer.
@MainActor
final class WindowManager {
    let captureArea: CaptureAreaController
    let viewer: ViewerWindowController

    init(settings: SettingsStore, permissions: PermissionsManager) {
        captureArea = CaptureAreaController(settings: settings)
        viewer = ViewerWindowController(permissions: permissions)
    }

    func showAll() {
        captureArea.show()
        showViewer()
    }

    func showViewer() {
        viewer.showWindow(nil)
        viewer.window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    var isViewerVisible: Bool { viewer.window?.isVisible ?? false }

    func toggleCaptureArea() {
        captureArea.toggle()
    }
}
