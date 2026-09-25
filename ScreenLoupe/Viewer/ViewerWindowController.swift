import AppKit

/// The Viewer: a regular, resizable window that can go full screen or live on another display. It
/// shows `ViewerContentView`, or the permission explanation while Screen Recording access is missing.
@MainActor
final class ViewerWindowController: NSWindowController, NSWindowDelegate {
    /// Called when the user closes the Viewer.
    var onClose: (() -> Void)?
    /// Called when the content switches between the permission explanation and the capture.
    var onPermissionChange: (() -> Void)?
    /// Called when the user asks to try capturing again after a failure.
    var onRetry: (() -> Void)?

    private let permissions: PermissionsManager
    private let settings: SettingsStore
    private let zoomPan: ZoomPanController
    private let content: ViewerContentView
    private let toolbar: ViewerToolbar
    private var showsPermissionView: Bool?
    /// ScreenCaptureKit refused for lack of permission although the preflight said yes. The
    /// preflight can stay stale until relaunch, so this holds until then.
    private var permissionDeniedByCapture = false
    private let hasSavedFrame: Bool

    init(
        permissions: PermissionsManager, settings: SettingsStore, frameStore: FrameStore, zoomPan: ZoomPanController,
        inspector: PixelInspector, project: ProjectStore
    ) {
        self.permissions = permissions
        self.settings = settings
        self.zoomPan = zoomPan
        content = ViewerContentView(
            settings: settings, frameStore: frameStore, zoomPan: zoomPan, inspector: inspector, project: project)
        toolbar = ViewerToolbar(
            zoomPan: zoomPan, settings: settings, ruler: content.ruler, selection: content.selection)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Screen Loupe"
        window.minSize = NSSize(width: 360, height: 260)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.toolbarStyle = .unified
        hasSavedFrame = window.setFrameUsingName("Viewer")
        super.init(window: window)
        window.delegate = self
        if !hasSavedFrame {
            window.center()
        }
        window.setFrameAutosaveName("Viewer")

        content.statusView.onRetry = { [weak self] in self?.onRetry?() }
        content.onShowCapture = { [weak self] in
            guard let self else { return }
            toolbar.setShowingCapture(isShowingCapture)
            onShowCapture?()
        }
        content.statusView.onRestart = { [weak self] in self?.permissions.relaunch() }
        settings.observe(\.viewerAlwaysOnTop) { [weak self] in self?.applyAlwaysOnTop($0) }
        refreshContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Whether the inspector is needed at all: for the crosshair or the Color Meter.
    var isInspecting: Bool {
        let current = settings.settings
        return current.crosshairEnabled || current.meterVisible
    }

    /// A short confirmation at the bottom of the Viewer, such as "View copied".
    func showToast(_ text: String) {
        content.showToast(text)
    }

    // MARK: First launch

    /// Puts a Viewer that has no saved frame beside the Capture Area rather than over it
    /// (docs/design.md §7, acceptance step 3): right of it, else left, else below, else above; clamped to the screen.
    func placeOnFirstLaunch(beside area: CGRect) {
        guard !hasSavedFrame, let window else { return }
        let screen =
            NSScreen.screens.first { $0.frame.contains(CGPoint(x: area.midX, y: area.midY)) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = window.frame.size
        let gap: CGFloat = 40
        let candidates = [
            CGPoint(x: area.maxX + gap, y: area.midY - size.height / 2),
            CGPoint(x: area.minX - gap - size.width, y: area.midY - size.height / 2),
            CGPoint(x: area.midX - size.width / 2, y: area.minY - gap - size.height),
            CGPoint(x: area.midX - size.width / 2, y: area.maxY + gap),
        ]
        let fits = candidates.first { visible.contains(CGRect(origin: $0, size: size)) }
        let origin = fits ?? candidates[0]
        let clamped = CGPoint(
            x: min(max(origin.x, visible.minX), visible.maxX - size.width),
            y: min(max(origin.y, visible.minY), visible.maxY - size.height)
        )
        window.setFrameOrigin(clamped)
    }

    // MARK: Keep on top

    var isAlwaysOnTop: Bool { settings.settings.viewerAlwaysOnTop }

    func toggleAlwaysOnTop() {
        settings.update { $0.viewerAlwaysOnTop.toggle() }
    }

    /// Keep on Top was turned on while the Viewer was full screen: it applies once that has ended.
    private var onTopAfterFullScreen = false
    /// Keep on Top was turned off while the Viewer floated over another app's full-screen Space: it
    /// waits, hidden, for a Space change to come back on an ordinary one.
    private var spaceObserver: NSObjectProtocol?

    /// On top, the Viewer floats above other apps' windows even while another app is active, and
    /// joins every Space, full-screen apps' included, like the Capture Area frame, which sits higher
    /// still (`.statusBar`) so the Viewer never covers it. A window that joins other apps' full-screen
    /// Spaces can't go full screen itself, so a full-screen Viewer leaves full screen first.
    private func applyAlwaysOnTop(_ onTop: Bool) {
        guard let window else { return }
        if onTop, window.styleMask.contains(.fullScreen) {
            onTopAfterFullScreen = true
            window.toggleFullScreen(nil)
            return
        }
        window.level = onTop ? .floating : .normal
        if onTop {
            if spaceObserver != nil {
                stopWaitingForSpace()
                window.orderFront(nil)
            }
            window.collectionBehavior.remove(.fullScreenPrimary)
            window.collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary])
        } else {
            _ = stepOutOfFullScreenSpace()
            window.collectionBehavior.remove([.canJoinAllSpaces, .fullScreenAuxiliary])
            window.collectionBehavior.insert(.fullScreenPrimary)
            // Back among ordinary windows, the Viewer would sit under another app's window ordered
            // front while it floated: it comes to their top, as the app it belongs to is active.
            if window.isVisible, NSApp.isActive { window.orderFront(nil) }
        }
    }

    /// Keep on Top is going off. A window that leaves every Space but one stays in the Space
    /// showing: over another app's full-screen Space it would stay stuck there. It hides instead and
    /// comes back when an ordinary Space shows. Returns that app, which keeps the focus.
    func stepOutOfFullScreenSpace() -> NSRunningApplication? {
        guard let window, window.isVisible, let app = window.screen?.otherAppInFullScreen else { return nil }
        window.orderOut(nil)
        waitForOrdinarySpace()
        return app
    }

    private func waitForOrdinarySpace() {
        guard spaceObserver == nil, let window else { return }
        let frame = window.frame
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let screen = NSScreen.screens.first { $0.frame.intersects(frame) }
                guard screen?.otherAppInFullScreen == nil else { return }
                self.stopWaitingForSpace()
                self.window?.orderFront(nil)
            }
        }
    }

    private func stopWaitingForSpace() {
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
        spaceObserver = nil
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        guard onTopAfterFullScreen else { return }
        onTopAfterFullScreen = false
        applyAlwaysOnTop(settings.settings.viewerAlwaysOnTop)
    }

    // MARK: Copy View

    /// What the Viewer shows, rendered offscreen (docs/design.md §2.4). `nil` without a frame.
    func renderViewImage(showsGrid: Bool) -> CGImage? {
        content.viewerView.renderViewImage(showsGrid: showsGrid)
    }

    // MARK: Ruler

    var isRulerOn: Bool { content.ruler.isOn }

    /// Turning the ruler off forgets it; turning it on starts a new one.
    func toggleRuler() {
        content.ruler.toggle()
    }

    // MARK: Select tool

    var isSelectToolOn: Bool { content.selection.isToolOn }

    /// Whether Copy View and Save View take the Select tool's selection rather than the whole view.
    var hasSelection: Bool { content.selection.selection != nil }

    func toggleSelectTool() {
        content.selection.toggleTool()
    }

    // MARK: Recent Captures

    /// Whether a recent capture shows in place of the live view (docs/product.md, Recent Captures).
    var isShowingCapture: Bool { content.isShowingCapture }

    /// Called when a recent capture starts or stops showing.
    var onShowCapture: (() -> Void)?

    /// Keeps what `image` was made from as a recent capture; see `ViewerContentView.captureKeeper`.
    func captureKeeper(_ kind: ViewerContentView.CaptureKind, image: CGImage) -> (() -> Void)? {
        content.captureKeeper(kind, image: image)
    }

    /// Back to the live view: closing the Viewer, Escape.
    func showLive() {
        content.captures.show(nil)
    }

    // MARK: Freeze frame

    /// Frozen, counting down to a freeze, or live: the image area and the toolbar's pause button.
    func showFreeze(_ state: FrozenIndicatorView.State) {
        content.showFreeze(state)
        toolbar.setFrozen(state != .hidden)
    }

    // MARK: Size to area

    /// Whether Size Window to Area can act: the capture is shown and the window isn't full screen.
    var canSizeToArea: Bool {
        guard let window else { return false }
        return showsCapture && zoomPan.state.contentSize.width > 0 && !window.styleMask.contains(.fullScreen)
    }

    /// Sizes the window so the whole magnified Capture Area shows at the current zoom. The window
    /// never grows beyond its screen; a bigger image still pans (docs/product.md, Viewer).
    func sizeToArea() {
        guard canSizeToArea, let window, let screen = window.screen else { return }
        let image = zoomPan.state.scaledContentSize
        let drawableScale = content.viewerView.drawableScale
        let chrome = CGSize(
            width: window.frame.width - content.imageAreaSize.width,
            height: window.frame.height - content.imageAreaSize.height)
        let frame = ViewerWindowFit.frame(
            imageSize: CGSize(width: image.width / drawableScale, height: image.height / drawableScale),
            chrome: chrome, window: window.frame, visible: screen.visibleFrame, minSize: window.minSize,
            scale: window.backingScaleFactor)
        window.setFrame(frame, display: true, animate: true)
    }

    // MARK: Content

    /// Whether the Viewer shows the capture rather than the permission explanation.
    var showsCapture: Bool { showsPermissionView == false }

    func frameArrived() {
        content.viewerView.frameArrived()
    }

    /// Shows or clears an interrupted capture.
    func setCaptureProblem(_ problem: CaptureProblem?) {
        let statusView = content.statusView
        let wasInterrupted = !statusView.isHidden
        switch problem {
        case .permissionDenied?:
            permissionDeniedByCapture = true
            hideStatus()
            refreshContent()
        case .reconnecting(let reason, let attempt, let maxAttempts, let nextAttempt)?:
            statusView.showReconnecting(reason: reason, attempt: attempt, of: maxAttempts, nextAttempt: nextAttempt)
            statusView.isHidden = false
        case .failed(let reason, let afterUserRetry)?:
            statusView.showFailed(reason: reason, afterUserRetry: afterUserRetry)
            statusView.isHidden = false
        case nil:
            hideStatus()
            if wasInterrupted, showsCapture {
                showToast("Capture restored")
            }
        }
    }

    private func hideStatus() {
        content.statusView.stop()
        content.statusView.isHidden = true
    }

    func windowDidBecomeKey(_ notification: Notification) {
        content.viewerView.requestDraw()
    }

    func windowWillClose(_ notification: Notification) {
        // Closed while waiting to come back: it stays closed.
        stopWaitingForSpace()
        onClose?()
    }

    /// Swaps between the permission explanation and the capture when the permission state changes.
    func refreshContent() {
        let needsPermission = !permissions.hasScreenRecordingAccess || permissionDeniedByCapture
        guard needsPermission != showsPermissionView else { return }
        showsPermissionView = needsPermission
        window?.toolbar = needsPermission ? nil : toolbar.toolbar
        window?.contentView = needsPermission ? PermissionView(permissions: permissions) : content
        if !needsPermission {
            window?.makeFirstResponder(content.viewerView)
        }
        onPermissionChange?()
    }
}
