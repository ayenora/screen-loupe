import AppKit

/// Owns the two independent windows — the Capture Area overlay and the Viewer — and the capture
/// stream between them.
@MainActor
final class WindowManager {
    let captureArea: CaptureAreaController
    let viewer: ViewerWindowController
    let export: ExportController
    private let capture = ScreenCaptureManager()
    private let zoomPan = ZoomPanController()
    private let project = ProjectStore()
    private let settings: SettingsStore
    private let inspector: PixelInspector
    /// Tracked here: during `windowWillClose` the window still reports itself visible.
    private var isViewerOpen = false

    init(settings: SettingsStore, permissions: PermissionsManager) {
        self.settings = settings
        zoomPan.restoredZoom = settings.settings.viewerZoom.map { CGFloat($0) }
        inspector = PixelInspector(frameStore: capture.frameStore, settings: settings)
        captureArea = CaptureAreaController(settings: settings)
        viewer = ViewerWindowController(
            permissions: permissions, settings: settings, frameStore: capture.frameStore, zoomPan: zoomPan,
            inspector: inspector, project: project)
        export = ExportController(frameStore: capture.frameStore, settings: settings, viewer: viewer)

        capture.onFrame = { [weak self] in
            self?.viewer.frameArrived()
            self?.inspector.frameArrived()
        }
        // Stop Sharing in the system menu acts like closing the Viewer: both windows go away.
        capture.onUserStopped = { [weak self] in self?.viewer.close() }
        capture.onProblem = { [weak self] problem in self?.viewer.setCaptureProblem(problem) }
        viewer.onRetry = { [weak self] in self?.capture.retry() }
        viewer.onPermissionChange = { [weak self] in self?.updateCapture() }
        // Closing the Viewer hides the Capture Area too; the app stays in the menu bar.
        viewer.onClose = { [weak self] in
            guard let self else { return }
            isViewerOpen = false
            setFrozen(false)
            saveViewerState()
            captureArea.hide()
            updateCapture()
            trackCursor()
        }
        captureArea.onChange = { [weak self] in
            self?.updateCapture()
            self?.trackCursor()
        }
        captureArea.onMouseMoved = { [weak self] in self?.trackCursor() }
        viewer.placeOnFirstLaunch(beside: captureArea.captureRect)
    }

    // MARK: The real cursor over the Capture Area

    /// Follows the real cursor while the Viewer is open, so the crosshair and the Color Meter show
    /// the pixel it points at inside the Capture Area (docs/product.md, Crosshair). The Capture Area
    /// reports mouse moves while it is shown; without it there is nothing to point at.
    private func trackCursor() {
        guard isViewerOpen, viewer.isInspecting, captureArea.isVisible,
            let scale = captureArea.captureGeometry?.display.scale
        else {
            inspector.setAreaPixel(nil)
            return
        }
        inspector.setAreaPixel(
            DisplayCoordinateConverter.areaPixel(
                at: NSEvent.mouseLocation, inArea: captureArea.captureRect, scale: scale))
    }

    /// Brings the Viewer forward. A Viewer that was closed comes back together with its Capture Area.
    func showViewer() {
        if !isViewerOpen {
            captureArea.show()
        }
        isViewerOpen = true
        trackCursor()
        viewer.showWindow(nil)
        viewer.window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        updateCapture()
    }

    func toggleCaptureArea() {
        captureArea.toggle()
        trackCursor()
    }

    /// The global Show / Hide Viewer shortcut. Hiding closes the Viewer, which hides the frame too.
    /// A Viewer that is open but can't be seen (minimized, the app hidden, another Space) comes
    /// forward instead.
    func toggleViewer() {
        if isViewerOpen, !NSApp.isHidden, let window = viewer.window, window.isVisible, window.isOnActiveSpace {
            viewer.close()
        } else {
            showViewer()
        }
    }

    // MARK: Freeze frame

    var isFrozen: Bool { capture.frameStore.isFrozen }

    /// Space in the Viewer, the toolbar's pause button, View › Freeze Frame.
    func toggleFreeze() {
        guard isFrozen || export.canExport else { return NSSound.beep() }
        setFrozen(!isFrozen)
    }

    private func setFrozen(_ frozen: Bool) {
        capture.frameStore.isFrozen = frozen
        viewer.setFrozen(frozen)
    }

    func resetZoom() {
        zoomPan.fit()
    }

    /// The zoom is kept between launches (docs/product.md, Kept between launches); the Viewer's frame is kept by AppKit.
    /// Writes the project now, before the app quits.
    func saveProject() {
        project.saveNow()
    }

    func saveViewerState() {
        guard zoomPan.state.contentSize.width > 0 else { return }
        settings.update { $0.viewerZoom = Double(zoomPan.state.zoom) }
    }

    #if DEBUG
        func simulateCaptureInterruption(recovers: Bool) {
            capture.simulateInterruption(recovers: recovers)
        }
    #endif

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
