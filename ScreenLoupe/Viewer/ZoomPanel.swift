import AppKit

/// The zoom panel's floating style: the zoom presets and field (`ZoomControls`) one under another in
/// a thin utility window beside the Viewer, as the studio's palette holds its buttons.
///
/// A child window of the Viewer (`ViewerWindowController` adds and removes it), so it stays above
/// the Viewer and moves with it; dragged by any place but a button, it goes anywhere, and the
/// Viewer keeps it where it was left relative to itself. It isn't resizable. Its buttons take the
/// first click and leave the Viewer key, so the keys still go to the image; the field makes the panel
/// key while it is edited (`becomesKeyOnlyIfNeeded`). The app is active whenever the panel is
/// clicked, so its buttons are named by tooltips.
@MainActor
final class ZoomPanel: NSPanel {
    let controls: ZoomControls
    /// Called by the close button and ⌘W: the zoom panel is turned off; the window is only ordered out.
    var onClose: (() -> Void)?
    /// Called after every move of the panel; the Viewer tells its own moves from the user's.
    var onMoved: (() -> Void)?

    init(zoomPan: ZoomPanController) {
        let margin = StudioPlacement.paletteMargin
        controls = ZoomControls(
            zoomPan: zoomPan, orientation: .vertical,
            insets: NSEdgeInsets(top: margin, left: margin, bottom: margin, right: margin))
        super.init(
            contentRect: .zero, styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        title = ""
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        hasShadow = true
        isMovableByWindowBackground = true
        becomesKeyOnlyIfNeeded = true
        // Shown with the Viewer, which stays while another app is active.
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        tabbingMode = .disallowed
        collectionBehavior = [.ignoresCycle]
        contentView = controls
        setContentSize(controls.fittingSize)
        // The close button turns the panel off, not `close()`: AppKit also calls `close()` on every
        // window when the app quits, which mustn't turn it off for the next launch.
        standardWindowButton(.closeButton)?.target = self
        standardWindowButton(.closeButton)?.action = #selector(performClose(_:))

        // Posted on the main thread and delivered at once, so the Viewer's moves are still marked.
        _ = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: self, queue: nil) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.onMoved?() }
        }
    }

    /// Key only while its field is edited: made key by a click on its title bar or background, it
    /// gives the keys back to the Viewer once the click is over.
    override func becomeKey() {
        super.becomeKey()
        DispatchQueue.main.async { [weak self] in
            guard let self, isKeyWindow, !(firstResponder is NSText) else { return }
            parent?.makeKey()
        }
    }

    /// Leaving the panel ends an edit of the field, as leaving the strip's does: a click on the
    /// Viewer drops a half-typed value and the field shows the zoom again.
    override func resignKey() {
        super.resignKey()
        makeFirstResponder(nil)
    }

    /// The close button and ⌘W turn the zoom panel off; the panel stays, to be shown again.
    override func performClose(_ sender: Any?) { onClose?() }
}
