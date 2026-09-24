import AppKit

/// The Viewer: a regular, resizable window that can go full screen or live on another display.
@MainActor
final class ViewerWindowController: NSWindowController {
    private let permissions: PermissionsManager
    private var showsPermissionView: Bool?

    init(permissions: PermissionsManager) {
        self.permissions = permissions
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
        super.init(window: window)
        if !window.setFrameUsingName("Viewer") {
            window.center()
        }
        window.setFrameAutosaveName("Viewer")
        refreshContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Swaps between the permission explanation and the capture when the permission state changes.
    func refreshContent() {
        let needsPermission = !permissions.hasScreenRecordingAccess
        guard needsPermission != showsPermissionView else { return }
        showsPermissionView = needsPermission
        window?.contentView = needsPermission ? PermissionView(permissions: permissions) : ViewerContentView()
    }
}

/// The capture area of the Viewer. The Metal renderer replaces its contents in stage 6
/// (docs/design.md §7).
final class ViewerContentView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }
}
