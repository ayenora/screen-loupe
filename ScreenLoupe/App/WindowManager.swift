import AppKit

/// Owns the two independent windows — the Capture Area overlay and the Viewer — and the capture
/// stream between them.
@MainActor
final class WindowManager {
    let captureArea: CaptureAreaController
    let viewer: ViewerWindowController
    private let capture = ScreenCaptureManager()
    private let zoomPan = ZoomPanController()
    private let settings: SettingsStore
    private let inspector: PixelInspector
    private var mouseMonitors: [Any] = []
    /// Tracked here: during `windowWillClose` the window still reports itself visible.
    private var isViewerOpen = false

    init(settings: SettingsStore, permissions: PermissionsManager) {
        self.settings = settings
        inspector = PixelInspector(frameStore: capture.frameStore, settings: settings)
        captureArea = CaptureAreaController(settings: settings)
        viewer = ViewerWindowController(
            permissions: permissions, settings: settings, frameStore: capture.frameStore, zoomPan: zoomPan,
            inspector: inspector)

        capture.onFrame = { [weak self] in
            self?.viewer.frameArrived()
            self?.inspector.frameArrived()
        }
        // Stop Sharing in the system menu acts like closing the Viewer: both windows go away.
        capture.onUserStopped = { [weak self] in self?.viewer.close() }
        capture.onProblem = { [weak self] problem in self?.viewer.setCaptureProblem(problem) }
        viewer.onRetry = { [weak self] in self?.capture.retry() }
        viewer.onCopyView = { [weak self] in self?.copyView() }
        viewer.onSaveView = { [weak self] in self?.saveView() }
        viewer.onPermissionChange = { [weak self] in self?.updateCapture() }
        // Closing the Viewer hides the Capture Area too; the app stays in the menu bar.
        viewer.onClose = { [weak self] in
            guard let self else { return }
            isViewerOpen = false
            captureArea.hide()
            updateCapture()
            stopTrackingCursor()
        }
        captureArea.onChange = { [weak self] _ in
            self?.updateCapture()
            self?.trackCursor()
        }
        viewer.placeOnFirstLaunch(beside: captureArea.captureRect)
    }

    // MARK: The real cursor over the Capture Area

    /// Follows the real cursor while the Viewer is open, so the crosshair and the Color Meter show
    /// the pixel it points at inside the Capture Area (docs/product.md, "Cursor in the Viewer").
    private func startTrackingCursor() {
        guard mouseMonitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        if let monitor = NSEvent.addGlobalMonitorForEvents(
            matching: mask,
            handler: { [weak self] _ in
                MainActor.assumeIsolated { self?.trackCursor() }
            })
        {
            mouseMonitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: mask,
            handler: { [weak self] event in
                MainActor.assumeIsolated { self?.trackCursor() }
                return event
            })
        {
            mouseMonitors.append(monitor)
        }
        trackCursor()
    }

    private func stopTrackingCursor() {
        mouseMonitors.forEach(NSEvent.removeMonitor)
        mouseMonitors.removeAll()
        inspector.setAreaPixel(nil)
    }

    private func trackCursor() {
        guard viewer.isInspecting, captureArea.isVisible, let scale = captureArea.captureGeometry?.display.scale
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
        startTrackingCursor()
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

    #if DEBUG
        func simulateCaptureInterruption(failingAttempts: Int) {
            capture.simulateInterruption(failingAttempts: failingAttempts)
        }
    #endif

    // MARK: Screenshots (TASK.md §7)

    /// Whether there is a frame to copy or save.
    var canExport: Bool { viewer.showsCapture && capture.frameStore.latestFrame != nil }

    func copyView() {
        guard let image = viewImage(), ScreenshotExporter.copy(image) else { return NSSound.beep() }
        viewer.showToast("View copied")
    }

    func copySource() {
        guard let image = sourceImage(), ScreenshotExporter.copy(image) else { return NSSound.beep() }
        viewer.showToast("Source copied")
    }

    func saveView() {
        save(viewImage(), kind: "View")
    }

    func saveSource() {
        save(sourceImage(), kind: "Source")
    }

    private func viewImage() -> CGImage? {
        guard let frame = capture.frameStore.latestFrame else { return nil }
        let colorSpace = NSScreen.colorSpace(forDisplay: frame.geometry.display.id)
        let clear = ViewerRenderer.backgroundColor
        guard
            let background = CGColor(
                colorSpace: colorSpace,
                components: [clear.red, clear.green, clear.blue, clear.alpha].map { CGFloat($0) })
        else { return nil }
        return ScreenshotExporter.viewImage(
            from: frame, state: zoomPan.state, background: background, colorSpace: colorSpace)
    }

    private func sourceImage() -> CGImage? {
        guard let frame = capture.frameStore.latestFrame else { return nil }
        return ScreenshotExporter.sourceImage(
            from: frame, colorSpace: NSScreen.colorSpace(forDisplay: frame.geometry.display.id))
    }

    /// The image is taken when the command is given, before the save panel opens.
    private func save(_ image: CGImage?, kind: String) {
        guard let image, let png = ScreenshotExporter.pngData(image), let window = viewer.window else {
            return NSSound.beep()
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = ScreenshotExporter.fileName(kind: kind)
        panel.directoryURL =
            settings.settings.screenshotDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try png.write(to: url, options: .atomic)
                self?.settings.update { $0.screenshotDirectory = url.deletingLastPathComponent().path }
                self?.viewer.showToast("Saved \(url.lastPathComponent)")
            } catch {
                NSAlert(error: error).beginSheetModal(for: window)
            }
        }
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
