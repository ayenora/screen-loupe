import AppKit

/// Owns the two independent windows — the Capture Area overlay and the Viewer — and the capture
/// stream between them.
@MainActor
final class WindowManager {
    let captureArea: CaptureAreaController
    let viewer: ViewerWindowController
    private let capture = ScreenCaptureManager()
    private let zoomPan = ZoomPanController()
    /// Tracked here: during `windowWillClose` the window still reports itself visible.
    private var isViewerOpen = false

    init(settings: SettingsStore, permissions: PermissionsManager) {
        captureArea = CaptureAreaController(settings: settings)
        viewer = ViewerWindowController(
            permissions: permissions, settings: settings, frameStore: capture.frameStore, zoomPan: zoomPan)

        capture.onFrame = { [weak self] in self?.viewer.frameArrived() }
        // Stop Sharing in the system menu acts like closing the Viewer: both windows go away.
        capture.onUserStopped = { [weak self] in self?.viewer.close() }
        capture.onProblem = { [weak self] problem in self?.viewer.setCaptureProblem(problem) }
        viewer.onRetry = { [weak self] in self?.capture.retry() }
        captureArea.onChange = { [weak self] _ in self?.updateCapture() }
        viewer.onPermissionChange = { [weak self] in self?.updateCapture() }
        // Closing the Viewer hides the Capture Area too; the app stays in the menu bar.
        viewer.onClose = { [weak self] in
            guard let self else { return }
            isViewerOpen = false
            captureArea.hide()
            updateCapture()
        }
        viewer.placeOnFirstLaunch(beside: captureArea.captureRect)
    }

    /// Brings the Viewer forward. A Viewer that was closed comes back together with its Capture Area.
    func showViewer() {
        if !isViewerOpen {
            captureArea.show()
        }
        isViewerOpen = true
        viewer.showWindow(nil)
        viewer.window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        updateCapture()
    }

    func toggleCaptureArea() {
        captureArea.toggle()
    }

    func resetZoom() {
        zoomPan.fit()
    }

    func displaysChanged() {
        captureArea.screenParametersChanged()
        capture.displaysChanged()
        updateCapture()
    }

    /// Streams while the Viewer is open and allowed to capture. Stops otherwise, so the system's
    /// screen-recording indicator goes away together with the Viewer.
    private func updateCapture() {
        let active = isViewerOpen && viewer.showsCapture
        capture.capture(active ? captureArea.captureGeometry : nil)
    }
}
