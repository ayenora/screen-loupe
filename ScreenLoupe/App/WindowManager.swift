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
            // A recent capture in the Viewer stays put; the live frame waits in the store.
            guard let self, !viewer.isShowingCapture else { return }
            viewer.frameArrived()
            inspector.frameArrived()
        }
        viewer.onShowCapture = { [weak self] in
            guard let self else { return }
            // A delayed freeze is for the live view it counted over.
            if viewer.isShowingCapture { cancelFreezeCountdown() }
            trackCursor()
        }
        // The eyedropper comes first: while it is on, the capture leaves the pointer out, so the
        // Color Meter never reads the pointer itself.
        settings.observe(\.capturesCursor) { [weak self] in self?.capture.showsCursor = $0 }
        // Stop Sharing in the system menu acts like closing the Viewer: both windows go away.
        capture.onUserStopped = { [weak self] in self?.viewer.close() }
        capture.onProblem = { [weak self] problem in self?.viewer.setCaptureProblem(problem) }
        viewer.onRetry = { [weak self] in self?.capture.retry() }
        viewer.onPermissionChange = { [weak self] in self?.updateCapture() }
        // Closing the Viewer hides the Capture Area too; the app stays in the menu bar.
        viewer.onClose = { [weak self] in
            guard let self else { return }
            isViewerOpen = false
            viewer.showLive()
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
        // The frame's raise button: a click in the area may have sent another app's window over the Viewer.
        captureArea.onRaiseViewer = { [weak self] in self?.showViewer() }
        captureArea.onPickWindow = { [weak self] in self?.pickWindow() }
        viewer.placeOnFirstLaunch(beside: captureArea.captureRect)
    }

    // MARK: The real cursor over the Capture Area

    /// Follows the real cursor while the Viewer is open, so the crosshair and the Color Meter show
    /// the pixel it points at inside the Capture Area (docs/product.md, Crosshair and cursor). The Capture Area
    /// reports mouse moves while it is shown; without it there is nothing to point at.
    private func trackCursor() {
        // On a recent capture the real cursor points at nothing in the picture.
        guard isViewerOpen, viewer.isInspecting, captureArea.isVisible, !viewer.isShowingCapture,
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

    /// Makes the Capture Area a window the user picks; a closed Viewer opens to show it.
    func pickWindow() {
        captureArea.pickWindow { [weak self] in
            guard let self, !isViewerOpen else { return }
            showViewer()
        }
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
    /// A delayed freeze is counting down (docs/product.md, Freeze frame).
    var isFreezeCountingDown: Bool { freezeTimer != nil }
    private var freezeTimer: Timer?

    /// Space in the Viewer, the toolbar's pause button, View › Freeze Frame, the global shortcut.
    /// During a countdown it stops the countdown instead. `hint` says how it was frozen, after the
    /// global shortcut from another app.
    func toggleFreeze(hint: String? = nil) {
        // Freezing is for the live view; a recent capture is still anyway.
        guard !viewer.isShowingCapture else { return }
        if isFreezeCountingDown { return cancelFreezeCountdown() }
        guard isFrozen || export.canExport else { return NSSound.beep() }
        setFrozen(!isFrozen, hint: hint)
    }

    /// Freezes at once, also in the middle of a countdown.
    func freezeNow() {
        guard !viewer.isShowingCapture else { return }
        cancelFreezeCountdown()
        guard isFrozen || export.canExport else { return NSSound.beep() }
        setFrozen(true)
    }

    /// Freezes after `seconds`, while the live view runs on: time to go to another app and press
    /// and hold there. A frozen view goes live for the countdown.
    func freeze(after seconds: Int) {
        guard !viewer.isShowingCapture else { return }
        guard isFrozen || export.canExport else { return NSSound.beep() }
        setFrozen(false)
        let total = TimeInterval(seconds)
        freezeTimer = Timer.scheduledTimer(withTimeInterval: total, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.freezeNow() }
        }
        viewer.showFreeze(.countdown(deadline: Date().addingTimeInterval(total), total: total))
    }

    /// Escape in the Viewer, the pause button during a countdown, closing the Viewer.
    func cancelFreezeCountdown() {
        guard let freezeTimer else { return }
        freezeTimer.invalidate()
        self.freezeTimer = nil
        viewer.showFreeze(isFrozen ? .frozen(hint: nil) : .hidden)
    }

    private func setFrozen(_ frozen: Bool, hint: String? = nil) {
        cancelFreezeCountdown()
        capture.frameStore.isFrozen = frozen
        viewer.showFreeze(frozen ? .frozen(hint: hint) : .hidden)
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

extension Settings {
    /// Whether the stream records the real pointer (docs/product.md, Crosshair and cursor): Original
    /// Cursor in the Capture is chosen and shown, and the eyedropper is off.
    var capturesCursor: Bool {
        crosshairEnabled && pointerStyle == .capturedCursor && !sidePanelLayout.isMeterExpanded
    }
}
