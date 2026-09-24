import AppKit

/// The Viewer: a regular, resizable window that can go full screen or live on another display.
@MainActor
final class ViewerWindowController: NSWindowController, NSWindowDelegate {
    /// Called when the user closes the Viewer.
    var onClose: (() -> Void)?
    /// Called when the content switches between the permission explanation and the capture.
    var onPermissionChange: (() -> Void)?
    /// Called when the user asks to try capturing again after a failure.
    var onRetry: (() -> Void)?
    /// The toolbar's Copy and Save buttons.
    var onCopyView: (() -> Void)?
    var onSaveView: (() -> Void)?

    private let permissions: PermissionsManager
    private let settings: SettingsStore
    private let viewerView: ViewerView
    private let statusView = CaptureStatusView()
    private let toast = ToastView()
    private let captureContent = NSView()
    private let toolbar: ViewerToolbar
    private var showsPermissionView: Bool?
    /// ScreenCaptureKit refused for lack of permission although the preflight said yes. The
    /// preflight can stay stale until relaunch, so this holds until then.
    private var permissionDeniedByCapture = false
    private let hasSavedFrame: Bool

    init(permissions: PermissionsManager, settings: SettingsStore, frameStore: FrameStore, zoomPan: ZoomPanController) {
        self.permissions = permissions
        self.settings = settings
        viewerView = ViewerView(frameStore: frameStore, zoomPan: zoomPan)
        toolbar = ViewerToolbar(zoomPan: zoomPan)

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

        buildCaptureContent()
        zoomPan.onChange = { [weak self] in
            self?.viewerView.requestDraw()
            self?.toolbar.refresh()
        }
        toolbar.onToggleAlwaysOnTop = { [weak self] in self?.toggleAlwaysOnTop() }
        toolbar.onCopy = { [weak self] in self?.onCopyView?() }
        toolbar.onSave = { [weak self] in self?.onSaveView?() }
        statusView.onRetry = { [weak self] in self?.onRetry?() }
        statusView.onRestart = { [weak self] in self?.permissions.relaunch() }
        applyAlwaysOnTop()
        refreshContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The magnified image, with the failure message centred over it when capturing failed.
    private func buildCaptureContent() {
        viewerView.frame = captureContent.bounds
        viewerView.autoresizingMask = [.width, .height]
        captureContent.addSubview(viewerView)
        statusView.isHidden = true
        statusView.translatesAutoresizingMaskIntoConstraints = false
        captureContent.addSubview(statusView)
        toast.translatesAutoresizingMaskIntoConstraints = false
        captureContent.addSubview(toast)
        NSLayoutConstraint.activate([
            statusView.centerXAnchor.constraint(equalTo: captureContent.centerXAnchor),
            statusView.centerYAnchor.constraint(equalTo: captureContent.centerYAnchor),
            toast.centerXAnchor.constraint(equalTo: captureContent.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: captureContent.bottomAnchor, constant: -16),
        ])
    }

    /// A short confirmation at the bottom of the Viewer, such as "View copied".
    func showToast(_ text: String) {
        toast.show(text)
    }

    // MARK: First launch

    /// Puts a Viewer that has no saved frame beside the Capture Area rather than over it
    /// (TASK.md §25.3): right of it, else left, else below, else above; clamped to the screen.
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
        applyAlwaysOnTop()
    }

    /// A floating window stays above other apps' windows even while another app is active. The
    /// Capture Area frame sits higher still (`.statusBar`), so the Viewer never covers it.
    private func applyAlwaysOnTop() {
        window?.level = isAlwaysOnTop ? .floating : .normal
        toolbar.setAlwaysOnTop(isAlwaysOnTop)
    }

    // MARK: Content

    /// Whether the Viewer shows the capture rather than the permission explanation.
    var showsCapture: Bool { showsPermissionView == false }

    func frameArrived() {
        viewerView.frameArrived()
    }

    /// Shows or clears an interrupted capture.
    func setCaptureProblem(_ problem: CaptureProblem?) {
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
        statusView.stop()
        statusView.isHidden = true
    }

    func windowDidBecomeKey(_ notification: Notification) {
        viewerView.requestDraw()
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    /// Swaps between the permission explanation and the capture when the permission state changes.
    func refreshContent() {
        let needsPermission = !permissions.hasScreenRecordingAccess || permissionDeniedByCapture
        guard needsPermission != showsPermissionView else { return }
        showsPermissionView = needsPermission
        window?.toolbar = needsPermission ? nil : toolbar.toolbar
        window?.contentView = needsPermission ? PermissionView(permissions: permissions) : captureContent
        if !needsPermission {
            window?.makeFirstResponder(viewerView)
        }
        onPermissionChange?()
    }
}
