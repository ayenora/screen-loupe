import AppKit
import OSLog

/// Owns the two independent windows — the Capture Area overlay and the Viewer — and the capture
/// stream between them, and the Screenshot studio beside them.
@MainActor
final class WindowManager {
    let captureArea: OverlayFrameController
    let viewer: ViewerWindowController
    let export: ExportController
    let studio: StudioController
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
        captureArea = OverlayFrameController(settings: settings)
        viewer = ViewerWindowController(
            permissions: permissions, settings: settings, frameStore: capture.frameStore, zoomPan: zoomPan,
            inspector: inspector, project: project)
        export = ExportController(frameStore: capture.frameStore, settings: settings, viewer: viewer)
        studio = StudioController(settings: settings, permissions: permissions, export: export)

        capture.onFrame = { [weak self] in
            // Take Snapshot takes the area's frame whatever the Viewer shows.
            self?.viewer.refreshSnapshot()
            // A still picture in the Viewer (frozen, a recent capture) stays put; the live frame
            // waits in the store.
            guard let self, capture.frameStore.still == nil else { return }
            // While the magnet moves the area the Viewer holds its frame; this one may end the hold.
            if magnetHold != nil { return checkMagnetHold() }
            viewer.frameArrived()
            inspector.frameArrived()
            updateViewedPart()
        }
        viewer.onShowCapture = { [weak self] in
            guard let self else { return }
            if viewer.isShowingCapture {
                magnetHoldEvent(.recentCaptureShown)
                // A delayed freeze is for the live view it counted over.
                cancelFreezeCountdown()
            }
            trackCursor()
            updateViewedPart()
        }
        // The frame outlines the part the Viewer shows, for a moment after the image pans or zooms,
        // and follows a zoom glide.
        zoomPan.observePresented { [weak self] in
            self?.updateViewedPart()
            self?.captureArea.flashViewedPart()
        }
        // The eyedropper comes first: while it is on, the capture leaves the pointer out, so the
        // Color Meter never reads the pointer itself.
        settings.observe(\.capturesCursor) { [weak self] in self?.capture.showsCursor = $0 }
        // Stop Sharing in the system menu acts like closing the Viewer: both windows go away.
        capture.onUserStopped = { [weak self] in self?.viewer.close() }
        capture.onProblem = { [weak self] problem in
            if problem != nil { self?.magnetHoldEvent(.captureInterrupted) }
            self?.viewer.setCaptureProblem(problem)
            self?.viewer.refreshSnapshot()
        }
        captureArea.onMagnetStopped = { [weak self] in self?.magnetHoldEvent(.magnetStopped) }
        viewer.onRetry = { [weak self] in self?.capture.retry() }
        viewer.onPermissionChange = { [weak self] in
            self?.magnetHoldEvent(.captureInterrupted)
            self?.updateCapture()
            self?.updateViewedPart()
        }
        // Closing the Viewer hides the Capture Area too; the app stays in the menu bar.
        viewer.onClose = { [weak self] in
            guard let self else { return }
            isViewerOpen = false
            magnetHoldEvent(.viewerClosed)
            viewer.showLive()
            setFrozen(false)
            saveViewerState()
            captureArea.hide()
            updateCapture()
            trackCursor()
            updateViewedPart()
        }
        captureArea.onChange = { [weak self] in
            guard let self else { return }
            if captureArea.isFollowingWindow {
                magnetMovedArea()
            } else {
                magnetHoldEvent(.areaChanged(to: captureArea.captureRect))
            }
            updateCapture()
            trackCursor()
        }
        captureArea.onMouseMoved = { [weak self] in self?.trackCursor() }
        captureArea.onViewportHandleDragBegan = { [weak self] in
            guard let self else { return }
            // The drag pans from the view as shown: a zoom glide stops there.
            zoomPan.settle()
            viewedPartDrag = ViewedPartDrag(
                start: zoomPan.state, startDelta: .zero, last: zoomPan.state, lastDelta: .zero)
        }
        captureArea.onViewportHandleDragged = { [weak self] in self?.dragViewedPart(by: $0) }
        // The frame's raise button: a click in the area may have sent another app's window over the Viewer.
        captureArea.onRaiseViewer = { [weak self] in self?.showViewer() }
        captureArea.onPickWindow = { [weak self] in self?.pickWindow() }
        // Its picker ends the studio's (`WindowPicker`) and a studio countdown, as the studio's own do.
        captureArea.onPickerStarted = { [weak self] in self?.studio.windowPickerStarted() }
        // The Viewer shows the studio's backdrop, as it shows the desktop it covers.
        studio.onBackdropChange = { [weak self] in self?.capture.keptWindow = $0 }
        // The studio has no permission flow of its own: the Viewer explains and asks.
        studio.capturedAppWindows = { [weak self] in
            guard let self else { return [] }
            return captureArea.windowNumbers + (viewer.window.map { [$0.windowNumber] } ?? [])
        }
        studio.onNeedsPermission = { [weak self] deniedByCapture in
            if deniedByCapture { self?.viewer.setCaptureProblem(.permissionDenied) }
            self?.showViewer()
        }
        viewer.placeOnFirstLaunch(beside: captureArea.captureRect)
    }

    // MARK: The real cursor over the Capture Area

    /// Follows the real cursor while the Viewer is open, so the crosshair and the Color Meter show
    /// the pixel it points at inside the Capture Area (docs/product.md, Crosshair and cursor). The Capture Area
    /// reports mouse moves while it is shown; without it there is nothing to point at.
    private func trackCursor() {
        // The real cursor points at a pixel of the live view or a frozen frame; at nothing in a
        // picture of its own, such as a recent capture.
        let still = capture.frameStore.still
        guard isViewerOpen, viewer.isInspecting, captureArea.isVisible, still == nil || still?.geometry != nil,
            let scale = captureArea.captureGeometry?.display.scale
        else {
            inspector.setAreaPixel(nil)
            return
        }
        inspector.setAreaPixel(
            DisplayCoordinateConverter.areaPixel(
                at: NSEvent.mouseLocation, inArea: captureArea.captureRect, scale: scale))
    }

    // MARK: The part the Viewer shows

    /// Tells the frame which part of the area the Viewer shows (docs/product.md, Capture Area), placed
    /// with the geometry of the frame the Viewer shows, so it matches the image even while the area
    /// is dragged ahead of the next frame. While the Viewer holds a frame as the magnet moves the
    /// area, on the area where it is (`MagnetHold.viewedPartGeometry`). Only of the live view
    /// (`showsLiveView`).
    private func updateViewedPart() {
        guard showsLiveView, let geometry = viewedPartGeometry else {
            captureArea.viewedPart = nil
            return
        }
        captureArea.viewedPart = DisplayCoordinateConverter.viewedPart(of: zoomPan.presented, in: geometry)?.rect
    }

    /// Whether the Viewer shows the live view of the area: a still picture (frozen, a recent capture)
    /// is of another moment, the area may have moved since, and a closed Viewer or one asking for
    /// permission shows nothing.
    private var showsLiveView: Bool {
        isViewerOpen && viewer.showsCapture && capture.frameStore.still == nil
    }

    /// The geometry the outline of the viewed part is placed with: the shown frame's, or during a
    /// hold `MagnetHold.viewedPartGeometry`.
    private var viewedPartGeometry: CaptureGeometry? {
        let shown = capture.frameStore.shownFrame?.geometry
        guard magnetHold != nil else { return shown }
        return MagnetHold.viewedPartGeometry(area: captureArea.captureGeometry, held: shown)
    }

    /// A drag of the viewport handle on the Capture Area, which pans the Viewer.
    private struct ViewedPartDrag {
        /// The view the drag pans from, and the pointer's move, in global points, when it was taken.
        var start: ZoomPanState
        var startDelta: CGVector
        /// The view the drag last set, and the pointer's move then.
        var last: ZoomPanState
        var lastDelta: CGVector
    }
    private var viewedPartDrag: ViewedPartDrag?

    /// Pans the Viewer so the outline follows the pointer, `delta` global points from where the drag
    /// began: from the view the drag started with, so whole-pixel rounding doesn't add up step by
    /// step. A view changed meanwhile by something else (a zoom, a resize) is taken as the new start.
    /// Only while the outline shows, on the geometry it is placed with.
    private func dragViewedPart(by delta: CGVector) {
        guard var drag = viewedPartDrag, showsLiveView, let geometry = viewedPartGeometry else { return }
        if zoomPan.state != drag.last {
            drag.start = zoomPan.state
            drag.startDelta = drag.lastDelta
        }
        let next = DisplayCoordinateConverter.panned(
            drag.start,
            draggingViewedPartBy: CGVector(dx: delta.dx - drag.startDelta.dx, dy: delta.dy - drag.startDelta.dy),
            in: geometry)
        zoomPan.pan(by: CGPoint(x: next.offset.x - zoomPan.state.offset.x, y: next.offset.y - zoomPan.state.offset.y))
        drag.last = zoomPan.state
        drag.lastDelta = delta
        viewedPartDrag = drag
    }

    /// Brings the Viewer forward. A Viewer that was closed comes back together with its Capture Area.
    func showViewer() {
        if !isViewerOpen {
            captureArea.show()
        }
        isViewerOpen = true
        trackCursor()
        updateViewedPart()
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

    /// Window › Reset Capture Area; a closed Viewer opens to show it, as for Fit to Window.
    func resetCaptureArea() {
        captureArea.reset()
        if !isViewerOpen { showViewer() }
        trackCursor()
    }

    /// The open panel is up, as a sheet on the Viewer or on its own; Open Image waits for it.
    private(set) var isChoosingImage = false

    /// File › Open Image… (docs/product.md, Open Image): the chosen image is decoded off the main
    /// thread, then shows in the Viewer, which opens for it. A file that can't be read changes
    /// nothing and says so.
    func openImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ImageFileLoader.openableTypes
        panel.message = "Choose an image to inspect in the Viewer."
        isChoosingImage = true
        let open: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            self?.isChoosingImage = false
            guard response == .OK, let url = panel.url, let self else { return }
            let request = viewer.newImageRequest()
            Task {
                let decoded = await ImageFileLoader.frame(at: url)
                // A later file was asked for, or the Viewer it was for has closed.
                guard self.viewer.isLatestImageRequest(request) else { return }
                guard let decoded else { return self.imageFailed(url) }
                self.showViewer()
                self.viewer.showImage(decoded.frame, thumbnail: decoded.thumbnail, name: url.lastPathComponent)
            }
        }
        if isViewerOpen, let window = viewer.window {
            panel.beginSheetModal(for: window, completionHandler: open)
        } else {
            NSApp.activate()
            open(panel.runModal())
        }
    }

    /// Edit › Paste as Reference or Paste for Inspection: the clipboard's image goes to `destination`
    /// in the Viewer, which opens for it. Nothing to paste beeps and opens nothing.
    func pasteImage(as destination: ImageDestination) {
        guard ImageInput.isOnClipboard else { return NSSound.beep() }
        showViewer()
        viewer.paste(as: destination)
    }

    private func imageFailed(_ url: URL) {
        let alert = NSAlert()
        alert.messageText = "The image couldn't be opened."
        alert.informativeText = url.lastPathComponent
        if isViewerOpen, let window = viewer.window {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
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
        let changed = frozen != isFrozen
        // Freezing during a hold freezes the held frame.
        capture.frameStore.isFrozen = frozen
        if frozen { magnetHoldEvent(.frozen) }
        viewer.showFreeze(frozen ? .frozen(hint: hint) : .hidden)
        // Live frames kept arriving while frozen: resuming shows the latest at once, not the frozen
        // one until the screen next changes.
        if changed {
            viewer.frameArrived()
            inspector.frameArrived()
        }
        updateViewedPart()
        viewer.refreshSnapshot()
    }

    // MARK: Holding while the magnet moves the area

    /// The Viewer holds its frame while the magnet moves the area with its window (`MagnetHold`);
    /// `nil` otherwise.
    private var magnetHold: MagnetHold?
    /// Checks the hold when no frame comes in to check it; runs only during a hold.
    private var magnetHoldTimer: Timer?

    /// The magnet moved the area: the live view holds the frame it shows, or goes on holding it.
    private func magnetMovedArea() {
        let now = ProcessInfo.processInfo.systemUptime
        if magnetHold != nil {
            magnetHold?.moved(to: captureArea.captureRect, at: now)
        } else {
            guard isViewerOpen, viewer.showsCapture else { return }
            capture.frameStore.hold()
            guard capture.frameStore.isHolding else { return }
            magnetHold = MagnetHold(movedTo: captureArea.captureRect, at: now)
        }
        if magnetHoldTimer == nil { scheduleMagnetHoldCheck(in: MagnetHold.settle) }
        updateViewedPart()
    }

    /// On each live frame, and once the window has been still for the settle time, since the frame
    /// of the area may have come in before: the hold ends if that frame is in.
    private func checkMagnetHold() {
        guard let magnetHold else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let shows = capture.frameStore.latestFrameShows(captureArea.captureGeometry)
        magnetHoldEvent(.check(at: now, showsArea: shows))
        if self.magnetHold != nil, magnetHoldTimer == nil, let wait = magnetHold.untilSettled(at: now) {
            scheduleMagnetHoldCheck(in: wait)
        }
    }

    private func scheduleMagnetHoldCheck(in seconds: TimeInterval) {
        let timer = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.magnetHoldTimer = nil
                self?.checkMagnetHold()
            }
        }
        // Also while a menu is open, as the magnet's own timer.
        RunLoop.main.add(timer, forMode: .common)
        magnetHoldTimer = timer
    }

    /// Ends the hold if `event` ends it (`MagnetHold.ends(on:)`). The live view goes on with the
    /// latest frame, unless a still picture or a closed Viewer takes its place.
    private func magnetHoldEvent(_ event: MagnetHold.Event) {
        guard let magnetHold, magnetHold.ends(on: event) else { return }
        #if DEBUG
            Logger(category: "magnet").debug("Hold ended: \(String(describing: event), privacy: .public)")
        #endif
        self.magnetHold = nil
        magnetHoldTimer?.invalidate()
        magnetHoldTimer = nil
        capture.frameStore.releaseHold()
        switch event {
        case .frozen, .recentCaptureShown, .viewerClosed:
            return
        case .check, .areaChanged, .magnetStopped, .displaysChanged, .captureInterrupted:
            // The area moved since the frame the Viewer last took: a move, not an edge drag.
            viewer.forgetAreaOrigin()
            viewer.frameArrived()
            inspector.frameArrived()
            updateViewedPart()
        }
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
        magnetHoldEvent(.displaysChanged)
        captureArea.screenParametersChanged()
        studio.screenParametersChanged()
        capture.displaysChanged()
        updateCapture()
    }

    /// Streams while the Viewer is open and allowed to capture. Stops otherwise, so the system's
    /// screen-recording indicator goes away together with the Viewer.
    private func updateCapture() {
        let active = isViewerOpen && viewer.canCapture
        capture.capture(active ? captureArea.captureGeometry : nil)
        viewer.refreshSnapshot()
    }
}

extension Settings {
    /// Whether the stream records the real pointer (docs/product.md, Crosshair and cursor): Original
    /// Cursor in the Capture is chosen and shown, and the eyedropper is off.
    var capturesCursor: Bool {
        crosshairEnabled && pointerStyle == .capturedCursor && !sidePanelLayout.isMeterExpanded
    }
}
