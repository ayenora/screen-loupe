import AppKit

/// Owns the two independent windows — the Capture Area overlay and the Viewer — and the capture
/// stream between them.
@MainActor
final class WindowManager {
    let captureArea: CaptureAreaController
    let viewer: ViewerWindowController
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
        viewer.onToggleFreeze = { [weak self] in self?.toggleFreeze() }
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
        guard isFrozen || canExport else { return NSSound.beep() }
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

    // MARK: Screenshots (docs/product.md, Screenshots)

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
        let current = settings.settings
        // The grid as the Viewer shows it, when Settings › Screenshots includes it.
        let showsGrid =
            current.gridEnabled && current.gridInCopyView && zoomPan.state.zoom >= CGFloat(current.gridMinimumZoom)
        return ScreenshotExporter.viewImage(
            from: frame, state: zoomPan.state, background: current.viewerBackground,
            checkerSquare: ViewerBackground.checkerSquare * viewer.drawableScale,
            grid: showsGrid ? current.gridLines : nil, references: viewer.referencesForExport,
            colorSpace: NSScreen.colorSpace(forDisplay: frame.geometry.display.id))
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
        panel.nameFieldStringValue = ScreenshotExporter.fileName(kind: kind, style: settings.settings.fileNameStyle)
        panel.directoryURL =
            settings.settings.screenshotDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try png.write(to: url, options: .atomic)
                self?.settings.update { $0.screenshotDirectory = url.deletingLastPathComponent().path }
                self?.viewer.showToast("Saved \(url.lastPathComponent)")
                if self?.settings.settings.revealsSavedFile == true {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
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
