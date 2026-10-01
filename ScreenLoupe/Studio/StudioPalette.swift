import AppKit

/// The Screenshot studio's palette: the Viewer's toolbar turned
/// upright — its buttons in groups on a thin utility window that can't be resized, dragged by any
/// place but a button and parked anywhere, apart from the frame. Its close button hides the studio.
///
/// A non-activating panel, so a click on it leaves the app the user works in active, and above every
/// other window (`WindowLevels.studioPalette`). AppKit shows tooltips only while the app is active,
/// so the palette names the hovered button itself, in a small label beside it. Its buttons call the
/// studio controller directly.
///
/// `NSToolbar` draws its own look: a `.toolbar`-bezel button outside a toolbar is bordered and shows
/// its on state in the accent colour. So the palette draws the toolbar's look itself (`ToolbarLook`).
@MainActor
final class StudioPalette: NSPanel, PaletteButtonHost {
    /// The window's width, the floating zoom panel's too: the last group, One Window and its ▾ alone,
    /// is the widest.
    static var width: CGFloat { ToolbarLook.current.paletteWidth }
    var onCapture: (() -> Void)?
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    /// Called with the Size button, to pop up the sizes from it.
    var onSize: ((PaletteButton) -> Void)?
    var onFitToWindow: (() -> Void)?
    var onToggleAspectLock: (() -> Void)?
    /// Called with the Timer button, to pop up the delays from it.
    var onTimer: ((PaletteButton) -> Void)?
    /// Called with the Output button, to pop up the format, colour and scale from it.
    var onOutput: ((PaletteButton) -> Void)?
    /// Called with the Background button, to pop up the backgrounds from it.
    var onBackground: ((PaletteButton) -> Void)?
    var onToggleOneWindow: (() -> Void)?
    /// Called when the ▾ beside One Window is clicked: the One Window menu to pop up
    /// (`popUpOneWindowMenu`).
    var onOneWindowMenu: (() -> Void)?
    /// Called by the close button: the studio hides; the palette is only ordered out.
    var onHide: (() -> Void)?
    /// Called when the user has dragged the palette to a new place.
    var onMoved: (() -> Void)?
    /// The studio's frame, in AppKit global coordinates: hover labels show on the palette's side away
    /// from it.
    var studioFrame: (() -> CGRect?)?

    /// One Window's mode. The One Window button, above the picker's panels, can end it while
    /// picking. While it is on, the controls that set the frame or the background are greyed and
    /// take no clicks (`OneWindowMode.usesFrame`).
    var oneWindowMode = OneWindowMode.off {
        didSet {
            updateOneWindowButton()
            for button in [sizeButton, fitToWindowButton, aspectLockButton, backgroundButton] {
                button.isEnabled = oneWindowMode.usesFrame
            }
        }
    }

    /// Filled while the window is picked and while one is chosen.
    private func updateOneWindowButton() {
        oneWindowButton.state = oneWindowMode != .off ? .on : .off
    }

    /// The palette's width level with the One Window button's slot, in AppKit global coordinates:
    /// One Window's notice sits beside it while no window's name shows.
    var oneWindowRow: CGRect {
        let slot = oneWindowButton.alignmentRect(forFrame: oneWindowButton.frame)
        let onScreen = convertToScreen(oneWindowButton.superview?.convert(slot, to: nil) ?? slot)
        return CGRect(x: frame.minX, y: onScreen.minY, width: frame.width, height: onScreen.height)
    }

    /// Filled while a background other than the screen is chosen.
    var hasBackground = false {
        didSet { backgroundButton.state = hasBackground ? .on : .off }
    }

    /// Filled while a delay is set.
    var hasDelay = false {
        didSet { timerButton.state = hasDelay ? .on : .off }
    }

    /// Filled while Aspect Lock is on.
    var aspectLocked = false {
        didSet { aspectLockButton.state = aspectLocked ? .on : .off }
    }

    /// While Fit to Window's picker runs: its button shows pressed, and a click on it, above the
    /// picker's panels, cancels.
    var isPickingWindow = false {
        didSet { fitToWindowButton.isPicking = isPickingWindow }
    }

    private let sizeButton = PaletteButton()
    private let fitToWindowButton = PaletteButton()
    private let aspectLockButton = PaletteButton()
    private let backgroundButton = PaletteButton()
    private let oneWindowButton = PaletteButton()
    /// The ▾ right of One Window, opening its menu.
    private let oneWindowMenuButton = PaletteButton()
    /// One Window and its ▾ side by side, the last group, alone.
    private lazy var oneWindowPair: NSStackView = {
        let row = NSStackView(views: [oneWindowButton, oneWindowMenuButton])
        row.orientation = .horizontal
        // The ▾'s view, as wide as its highlight, overlaps One Window by the overhang, so its 16 pt
        // slot starts where One Window's ends; it is later, so it is hit-tested first.
        row.spacing = -PaletteMenuButton.overhang(fillHeight: ToolbarLook.current.fillHeight)
        return row
    }()
    private let timerButton = PaletteButton()
    private let saveButton = PaletteButton()
    private lazy var hoverLabel = ButtonNameLabel(parent: self)
    /// Set when the user starts dragging the palette, until the button is up after a move.
    private var isDragged = false

    init() {
        super.init(
            contentRect: .zero, styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered, defer: false)
        title = ""
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        hasShadow = true
        // Dragged by any place but a button: the margins, the gaps and the groups' views all let
        // a mouse-down move the window, and the buttons don't.
        isMovableByWindowBackground = true
        acceptsMouseMovedEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        tabbingMode = .disallowed
        // After the style: a utility panel sets itself floating.
        level = NSWindow.Level(rawValue: WindowLevels.studioPalette)
        // Over a full-screen app's Space too.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        Self.configure(saveButton, "square.and.arrow.down", "Save…", #selector(saveClicked))
        Self.configure(sizeButton, "arrow.up.left.and.arrow.down.right", "Size", #selector(sizeClicked))
        Self.configure(fitToWindowButton, "rectangle.dashed", "Fit to Window", #selector(fitToWindowClicked))
        Self.configure(aspectLockButton, "aspectratio", "Aspect Lock", #selector(aspectLockClicked))
        aspectLockButton.makeToggle()
        aspectLockButton.alternateImage = NSImage(
            systemSymbolName: "aspectratio.fill", accessibilityDescription: "Aspect Lock")
        Self.configure(
            backgroundButton, "square.3.layers.3d.bottom.filled", "Background", #selector(backgroundClicked))
        backgroundButton.makeToggle()
        Self.configure(oneWindowButton, "macwindow", "One Window", #selector(oneWindowClicked))
        oneWindowButton.makeToggle()
        // A ▾ of its own right of it, as the Viewer toolbar's buttons with a menu have.
        oneWindowMenuButton.show(menuNamed: "One Window Options")
        oneWindowMenuButton.action = #selector(oneWindowMenuClicked)
        Self.configure(timerButton, "timer", "Timer", #selector(timerClicked))
        timerButton.makeToggle()

        // The toolbar's groups, apart as its items around a space are.
        let groups: [[NSView]] = [
            [
                Self.button("camera", "Capture — Copy and Save", #selector(captureClicked)),
                Self.button("doc.on.doc", "Copy", #selector(copyClicked)),
                saveButton,
            ],
            [
                sizeButton,
                fitToWindowButton,
                aspectLockButton,
                timerButton,
                Self.button("slider.horizontal.3", "Output", #selector(outputClicked)),
                backgroundButton,
            ],
            [oneWindowPair],
        ]
        for case let button as NSButton in groups.joined() + [oneWindowButton, oneWindowMenuButton] {
            button.target = self
        }
        let look = ToolbarLook.current
        let stack = NSStackView(views: groups.map { look.group($0) })
        stack.orientation = .vertical
        // The narrower groups centred over the last, One Window and its ▾.
        stack.alignment = .centerX
        stack.spacing = look.groupSpacing
        let margin = StudioPlacement.paletteMargin
        stack.edgeInsets = NSEdgeInsets(top: margin, left: margin, bottom: margin, right: margin)
        // Else a vertical stack's fitting width leaves out its side insets.
        stack.setHuggingPriority(.defaultHigh, for: .horizontal)
        let content = look.container(stack)
        contentView = content
        setContentSize(content.fittingSize)

        // A drag by the title bar or the background is the window server's: it starts with
        // `willMove` (a move by code posts none), and `didMove` follows while or once it ends.
        let center = NotificationCenter.default
        _ = center.addObserver(forName: NSWindow.willMoveNotification, object: self, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.isDragged = true }
        }
        _ = center.addObserver(forName: NSWindow.didMoveNotification, object: self, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isDragged else { return }
                if NSEvent.pressedMouseButtons & 1 == 0 { self.isDragged = false }
                self.onMoved?()
            }
        }
        // A new accent colour shows on the toggles that are on.
        _ = center.addObserver(forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                for button in [self.aspectLockButton, self.timerButton, self.backgroundButton, self.oneWindowButton] {
                    button.needsDisplay = true
                }
            }
        }
    }

    /// A click on a button goes to its action without first making the panel key.
    override var canBecomeKey: Bool { false }

    /// The close button hides the studio; the palette stays, to be shown again. The button's action
    /// calls `close()` directly, not `performClose(_:)`.
    override func close() { onHide?() }

    override func orderOut(_ sender: Any?) {
        endHover()
        isDragged = false
        super.orderOut(sender)
    }

    // MARK: Hover label

    /// Names `button` beside the palette after a short rest, or at once while the pointer goes on
    /// from a named button (`ButtonNameLabel`): on the palette's side away from the studio's frame
    /// (`StudioPlacement.hoverLabelX`), level with the button.
    func pointerEntered(_ button: PaletteButton) {
        guard let name = button.name else { return }
        hoverLabel.pointerEntered(ObjectIdentifier(button), name: name) { [weak self, weak button] size in
            guard let self, let button else { return nil }
            let buttonFrame = convertToScreen(button.convert(button.bounds, to: nil))
            let visible = screen?.visibleFrame ?? frame
            let x = StudioPlacement.hoverLabelX(width: size.width, beside: frame, frame: studioFrame?(), in: visible)
            return CGRect(origin: CGPoint(x: x, y: (buttonFrame.midY - size.height / 2).rounded()), size: size)
        }
    }

    func pointerExited(_ button: PaletteButton) {
        hoverLabel.pointerExited(ObjectIdentifier(button))
    }

    /// A click or hiding: the name goes, and the next button waits the full rest.
    func endHover() {
        hoverLabel.end()
    }

    // MARK: Buttons

    private static func button(_ symbol: String, _ title: String, _ action: Selector) -> PaletteButton {
        let button = PaletteButton()
        configure(button, symbol, title, action)
        return button
    }

    private static func configure(_ button: PaletteButton, _ symbol: String, _ title: String, _ action: Selector) {
        button.show(symbol: symbol, name: title)
        button.action = action
    }

    @objc private func captureClicked() { onCapture?() }
    @objc private func copyClicked() { onCopy?() }
    @objc private func saveClicked() { onSave?() }
    @objc private func sizeClicked(_ sender: PaletteButton) { onSize?(sender) }
    @objc private func fitToWindowClicked() { onFitToWindow?() }
    @objc private func outputClicked(_ sender: PaletteButton) { onOutput?(sender) }

    /// Shows the setting, not the click: the setting sets it back.
    @objc private func aspectLockClicked(_ sender: NSButton) {
        sender.state = aspectLocked ? .on : .off
        onToggleAspectLock?()
    }

    /// The button shows whether a background is chosen, not the click.
    @objc private func backgroundClicked(_ sender: PaletteButton) {
        sender.state = hasBackground ? .on : .off
        onBackground?(sender)
    }

    /// Shows the mode, not the click.
    @objc private func oneWindowMenuClicked() { onOneWindowMenu?() }

    /// Pops `menu` up beside the palette, its top level with `anchor`'s (the button itself by
    /// default), on the side away from the studio's frame (`StudioPlacement.menuTopLeft`), with
    /// `NSMenu.popUp(positioning:at:in:)` as the Viewer toolbar pops up its ▾ menus. Menu tracking
    /// is modal: `button` shows pressed until it returns. Nothing here activates the app: the menu is
    /// popped up from the non-activating palette as it is, and the app the user works in stays
    /// active (checked live).
    func popUp(_ menu: NSMenu, from button: PaletteButton, alignedWith anchor: PaletteButton? = nil) {
        let anchor = anchor ?? button
        guard let view = anchor.superview else { return }
        let slot = convertToScreen(view.convert(anchor.alignmentRect(forFrame: anchor.frame), to: nil))
        let visible = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? frame
        let topLeft = StudioPlacement.menuTopLeft(
            size: menu.size, beside: frame, anchorTop: slot.maxY, frame: studioFrame?(), in: visible)
        button.isListOpen = true
        defer { button.isListOpen = false }
        menu.popUp(positioning: nil, at: topLeft, in: nil)
    }

    /// The One Window menu beside the palette, its top level with One Window's.
    func popUpOneWindowMenu(_ menu: NSMenu) {
        popUp(menu, from: oneWindowMenuButton, alignedWith: oneWindowButton)
    }

    @objc private func oneWindowClicked(_ sender: NSButton) {
        updateOneWindowButton()
        onToggleOneWindow?()
    }

    /// Shows whether a delay is set, not the click.
    @objc private func timerClicked(_ sender: PaletteButton) {
        sender.state = hasDelay ? .on : .off
        onTimer?(sender)
    }

    /// A stretchable mask with rounded corners for the background.
    static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: CGSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
