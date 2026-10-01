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
    /// The window's width.
    static var width: CGFloat { StudioPlacement.paletteWidth(buttonWidth: ToolbarLook.current.buttonSize.width) }
    var onCapture: (() -> Void)?
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    /// Called with the Size button, to open the sizes beside it.
    var onSize: ((NSView) -> Void)?
    var onFitToWindow: (() -> Void)?
    var onToggleAspectLock: (() -> Void)?
    /// Called with the Timer button, to open the delays beside it.
    var onTimer: ((NSView) -> Void)?
    /// Called with the Output button, to open the format, colour and scale beside it.
    var onOutput: ((NSView) -> Void)?
    /// Called with the Background button, to open the backgrounds beside it.
    var onBackground: ((NSView) -> Void)?
    var onToggleOneWindow: (() -> Void)?
    var onTogglePointer: (() -> Void)?
    /// Called by the close button: the studio hides; the palette is only ordered out.
    var onHide: (() -> Void)?
    /// Called when a user's drag of the palette begins.
    var onDragStarted: (() -> Void)?
    /// Called when the user has dragged the palette to a new place.
    var onMoved: (() -> Void)?
    /// The studio's frame, in AppKit global coordinates: hover labels show on the palette's side away
    /// from it.
    var studioFrame: (() -> CGRect?)?

    /// While the window for One Window is picked; the One Window button, above the picker's panels,
    /// can cancel it.
    var isPickingOneWindow = false {
        didSet { updateOneWindowButton() }
    }

    /// Whether One Window has a window. Its pictures take the window alone, without the pointer, so
    /// Include the Pointer is off meanwhile, showing its setting.
    var hasOneWindow = false {
        didSet {
            updateOneWindowButton()
            pointerButton.isEnabled = !hasOneWindow
        }
    }

    /// Filled while the window is picked and while one is chosen.
    private func updateOneWindowButton() {
        oneWindowButton.state = isPickingOneWindow || hasOneWindow ? .on : .off
    }

    /// Filled while a background other than the screen is chosen.
    var hasBackground = false {
        didSet { backgroundButton.state = hasBackground ? .on : .off }
    }

    /// Filled while a delay is set.
    var hasDelay = false {
        didSet { timerButton.state = hasDelay ? .on : .off }
    }

    /// Filled while pictures include the pointer.
    var includesPointer = false {
        didSet { pointerButton.state = includesPointer ? .on : .off }
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

    /// The Size, Timer, Output or Background button whose list is open: it shows pressed until the list
    /// closes. Set by the studio when it opens a list, cleared when the list is ordered out.
    var openListButton: NSView? {
        didSet {
            guard openListButton !== oldValue else { return }
            (oldValue as? PaletteButton)?.isListOpen = false
            (openListButton as? PaletteButton)?.isListOpen = true
        }
    }

    private let fitToWindowButton = PaletteButton()
    private let aspectLockButton = PaletteButton()
    private let backgroundButton = PaletteButton()
    private let oneWindowButton = PaletteButton()
    private let timerButton = PaletteButton()
    private let pointerButton = PaletteButton()
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
        Self.configure(timerButton, "timer", "Timer", #selector(timerClicked))
        timerButton.makeToggle()
        Self.configure(pointerButton, "cursorarrow", "Include the Pointer", #selector(pointerClicked))
        pointerButton.makeToggle()

        // The toolbar's groups, apart as its items around a space are.
        let groups: [[NSView]] = [
            [
                Self.button("camera", "Capture — Copy and Save", #selector(captureClicked)),
                Self.button("doc.on.doc", "Copy", #selector(copyClicked)),
                saveButton,
            ],
            [
                Self.button("arrow.up.left.and.arrow.down.right", "Size", #selector(sizeClicked)),
                fitToWindowButton,
                aspectLockButton,
                timerButton,
                Self.button("slider.horizontal.3", "Output", #selector(outputClicked)),
            ],
            [backgroundButton, oneWindowButton, pointerButton],
        ]
        for case let button as NSButton in groups.joined() {
            button.target = self
        }
        let look = ToolbarLook.current
        let stack = NSStackView(views: groups.map { look.group($0) })
        stack.orientation = .vertical
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
            MainActor.assumeIsolated {
                self?.isDragged = true
                self?.onDragStarted?()
            }
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
                for button in [
                    self.aspectLockButton, self.timerButton, self.backgroundButton, self.oneWindowButton,
                    self.pointerButton,
                ] {
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
    @objc private func sizeClicked(_ sender: NSButton) { onSize?(sender) }
    @objc private func fitToWindowClicked() { onFitToWindow?() }
    @objc private func outputClicked(_ sender: NSButton) { onOutput?(sender) }

    /// Shows the setting, not the click: the setting sets it back.
    @objc private func aspectLockClicked(_ sender: NSButton) {
        sender.state = aspectLocked ? .on : .off
        onToggleAspectLock?()
    }

    /// The button shows whether a background is chosen, not the click.
    @objc private func backgroundClicked(_ sender: NSButton) {
        sender.state = hasBackground ? .on : .off
        onBackground?(sender)
    }

    /// Shows the mode, not the click.
    @objc private func oneWindowClicked(_ sender: NSButton) {
        updateOneWindowButton()
        onToggleOneWindow?()
    }

    /// Shows whether a delay is set, not the click.
    @objc private func timerClicked(_ sender: NSButton) {
        sender.state = hasDelay ? .on : .off
        onTimer?(sender)
    }

    /// Shows the setting, not the click.
    @objc private func pointerClicked(_ sender: NSButton) {
        sender.state = includesPointer ? .on : .off
        onTogglePointer?()
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
