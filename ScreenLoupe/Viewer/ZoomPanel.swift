import AppKit

/// The zoom panel's floating style: the zoom presets and field (`ZoomControls`) one under another in
/// a thin utility window beside the Viewer, as the studio's palette holds its buttons, and as wide.
///
/// A child window of the Viewer (`ViewerWindowController` adds and removes it), so it stays above
/// the Viewer and moves with it; dragged by any place but a button, it goes anywhere, and the
/// Viewer keeps it where it was left relative to itself. It isn't resizable. Its buttons take the
/// first click and leave the Viewer key, so the keys still go to the image. The app is active
/// whenever the panel is clicked, so its buttons are named by tooltips.
///
/// It never becomes key, as the palette never does: Liquid Glass draws its key-window look in a
/// key window, near white on the window's background (measured on macOS 27: a group's glass 243
/// grey, 252 while key; 70 and 80 in dark), so the groups would all but vanish while the field is
/// edited. The field is laid over its slot from a small transparent window of its own,
/// `ZoomFieldPanel`, a child of this one, which alone becomes key while the field is edited.
@MainActor
final class ZoomPanel: NSPanel {
    let controls: ZoomControls
    /// Called by the close button and ⌘W: the zoom panel is turned off; the window is only ordered out.
    var onClose: (() -> Void)?
    /// Called after every move of the panel; the Viewer tells its own moves from the user's.
    var onMoved: (() -> Void)?
    private let fieldPanel: ZoomFieldPanel

    init(zoomPan: ZoomPanController) {
        let margin = StudioPlacement.paletteMargin
        let look = ToolbarLook.current
        controls = ZoomControls(
            zoomPan: zoomPan, orientation: .vertical,
            insets: NSEdgeInsets(top: margin, left: margin, bottom: margin, right: margin),
            width: look.paletteWidth, fieldGroupRadius: ToolbarLook.fieldGroupRadius)
        fieldPanel = ZoomFieldPanel(field: controls.field)
        super.init(
            contentRect: .zero, styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        title = ""
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        hasShadow = true
        isMovableByWindowBackground = true
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
        fieldPanel.onClose = { [weak self] in self?.performClose(nil) }

        // Posted on the main thread and delivered at once, so the Viewer's moves are still marked.
        _ = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: self, queue: nil) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.onMoved?() }
        }
    }

    override var canBecomeKey: Bool { false }

    /// The field's window goes with the panel, over the field's slot, at its level.
    override var level: NSWindow.Level {
        didSet { fieldPanel.level = level }
    }

    override func orderFront(_ sender: Any?) {
        super.orderFront(sender)
        showField()
    }

    override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
        super.order(place, relativeTo: otherWin)
        if place != .out { showField() }
    }

    /// Lays the field's window over the field's slot and attaches it, once the panel shows.
    private func showField() {
        layoutIfNeeded()
        let slot = controls.fieldSlot
        fieldPanel.setFrame(convertToScreen(slot.convert(slot.bounds, to: nil)), display: false)
        if fieldPanel.parent == nil { addChildWindow(fieldPanel, ordered: .above) }
    }

    /// The close button and ⌘W turn the zoom panel off; the panel stays, to be shown again.
    override func performClose(_ sender: Any?) { onClose?() }
}

/// The zoom field's own window, over its slot in the zoom panel: borderless and transparent, the
/// panel's glass group showing through, so only it becomes key while the field is edited, and only
/// then (`becomesKeyOnlyIfNeeded`). Leaving it ends the edit, as leaving the strip's field does: a
/// click on the Viewer drops a half-typed value and the field shows the zoom again.
@MainActor
private final class ZoomFieldPanel: NSPanel {
    /// ⌘W while the field is edited: the zoom panel is turned off, as from the panel.
    var onClose: (() -> Void)?

    init(field: ZoomField) {
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Set explicitly, so the window takes clicks on its transparent parts too: anywhere over the
        // field's group, not only on the digits.
        ignoresMouseEvents = false
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        collectionBehavior = [.ignoresCycle]
        animationBehavior = .none
        // A click anywhere over the field's group starts the edit, as in the strip.
        let content = ZoomFieldBox(field: field)
        field.removeFromSuperview()
        field.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            field.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            field.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
        contentView = content
    }

    override var canBecomeKey: Bool { true }

    override func resignKey() {
        super.resignKey()
        makeFirstResponder(nil)
    }

    override func performClose(_ sender: Any?) { onClose?() }
}
