import AppKit

/// The Viewer: a regular, resizable window that can go full screen or live on another display.
@MainActor
final class ViewerWindowController: NSWindowController, NSWindowDelegate {
    /// Called when the user closes the Viewer.
    var onClose: (() -> Void)?
    /// Called when the content switches between the permission explanation and the capture.
    var onPermissionChange: (() -> Void)?

    private let permissions: PermissionsManager
    private let settings: SettingsStore
    private let viewerView: ViewerView
    private let toolbar: ViewerToolbar
    private var showsPermissionView: Bool?

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
        super.init(window: window)
        window.delegate = self
        if !window.setFrameUsingName("Viewer") {
            window.center()
        }
        window.setFrameAutosaveName("Viewer")

        zoomPan.onChange = { [weak self] in
            self?.viewerView.requestDraw()
            self?.toolbar.refresh()
        }
        toolbar.onToggleAlwaysOnTop = { [weak self] in self?.toggleAlwaysOnTop() }
        applyAlwaysOnTop()
        refreshContent()
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

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Whether the Viewer shows the capture rather than the permission explanation.
    var showsCapture: Bool { showsPermissionView == false }

    func frameArrived() {
        viewerView.frameArrived()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        viewerView.requestDraw()
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    /// Swaps between the permission explanation and the capture when the permission state changes.
    func refreshContent() {
        let needsPermission = !permissions.hasScreenRecordingAccess
        guard needsPermission != showsPermissionView else { return }
        showsPermissionView = needsPermission
        window?.toolbar = needsPermission ? nil : toolbar.toolbar
        window?.contentView = needsPermission ? PermissionView(permissions: permissions) : viewerView
        if !needsPermission {
            window?.makeFirstResponder(viewerView)
        }
        onPermissionChange?()
    }
}
