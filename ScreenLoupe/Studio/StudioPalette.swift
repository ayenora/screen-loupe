import AppKit

/// The Screenshot studio's palette (docs/product.md, Screenshot studio): the Viewer's toolbar turned
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
final class StudioPalette: NSPanel {
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

    /// The Size, Timer or Background button whose list is open: it shows pressed until the list
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
            ],
            [backgroundButton, oneWindowButton, pointerButton],
        ]
        for case let button as NSButton in groups.joined() {
            button.target = self
        }
        let look = ToolbarLook.current
        let stack = NSStackView(views: groups.map(look.group))
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
    fileprivate func pointerEntered(_ button: PaletteButton) {
        guard let name = button.name else { return }
        hoverLabel.pointerEntered(ObjectIdentifier(button), name: name) { [weak self, weak button] size in
            guard let self, let button else { return nil }
            let buttonFrame = convertToScreen(button.convert(button.bounds, to: nil))
            let visible = screen?.visibleFrame ?? frame
            let x = StudioPlacement.hoverLabelX(width: size.width, beside: frame, frame: studioFrame?(), in: visible)
            return CGRect(origin: CGPoint(x: x, y: (buttonFrame.midY - size.height / 2).rounded()), size: size)
        }
    }

    fileprivate func pointerExited(_ button: PaletteButton) {
        hoverLabel.pointerExited(ObjectIdentifier(button))
    }

    /// A click or hiding: the name goes, and the next button waits the full rest.
    fileprivate func endHover() {
        hoverLabel.end()
    }

    // MARK: Buttons

    private static func button(_ symbol: String, _ title: String, _ action: Selector) -> PaletteButton {
        let button = PaletteButton()
        configure(button, symbol, title, action)
        return button
    }

    private static func configure(_ button: PaletteButton, _ symbol: String, _ title: String, _ action: Selector) {
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.imagePosition = .imageOnly
        // At the symbol scale `NSToolbar` gives a `.toolbar`-bezel button's image (docs/design.md).
        button.symbolConfiguration = NSImage.SymbolConfiguration(scale: .large)
        button.imageScaling = .scaleNone
        button.contentTintColor = .labelColor
        button.name = title
        button.action = action
        let size = ToolbarLook.current.buttonSize
        button.widthAnchor.constraint(equalToConstant: size.width).isActive = true
        button.heightAnchor.constraint(equalToConstant: size.height).isActive = true
    }

    @objc private func captureClicked() { onCapture?() }
    @objc private func copyClicked() { onCopy?() }
    @objc private func saveClicked() { onSave?() }
    @objc private func sizeClicked(_ sender: NSButton) { onSize?(sender) }
    @objc private func fitToWindowClicked() { onFitToWindow?() }

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

/// The Viewer toolbar's look as `NSToolbar` draws it on this macOS. From macOS 26 its items sit
/// flush in Liquid Glass capsules as tall as the bar, 36 pt, 8 pt apart around a space, and a pressed
/// button shows a grey 30 × 28 pt capsule. Before, the items sit on the titlebar's material, and
/// a pressed button shows a rounded grey rect. A toggle that is on, in an active app, fills the same
/// shape with the accent colour under a near-white symbol (docs/design.md).
private struct ToolbarLook {
    let isGlass: Bool
    let buttonSize: CGSize
    let fillInset: CGSize
    /// `nil` for a capsule.
    let fillRadius: CGFloat?
    let groupRadius: CGFloat
    let groupSpacing: CGFloat = 8

    static let current: ToolbarLook =
        if #available(macOS 26.0, *) {
            ToolbarLook(
                isGlass: true, buttonSize: CGSize(width: 36, height: 36), fillInset: CGSize(width: 3, height: 4),
                fillRadius: nil, groupRadius: 18)
        } else {
            ToolbarLook(
                isGlass: false, buttonSize: CGSize(width: 32, height: 28), fillInset: CGSize(width: 2, height: 2),
                fillRadius: 6, groupRadius: 8)
        }

    /// `views` one under another on a group's background.
    @MainActor func group(_ views: [NSView]) -> NSView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.spacing = 0
        if #available(macOS 26.0, *), isGlass {
            let glass = NSGlassEffectView()
            glass.cornerRadius = groupRadius
            glass.contentView = stack
            return glass
        }
        let background = NSVisualEffectView()
        background.material = .titlebar
        background.blendingMode = .behindWindow
        background.state = .active
        background.maskImage = StudioPalette.roundedMask(radius: groupRadius)
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        return background
    }

    /// The groups' holder: with glass, a container, so the capsules are drawn together as the
    /// toolbar's are.
    @MainActor func container(_ groups: NSView) -> NSView {
        if #available(macOS 26.0, *), isGlass {
            let container = NSGlassEffectContainerView()
            container.contentView = groups
            return container
        }
        return groups
    }

    /// The on or pressed fill of a button whose slot is `slot`.
    @MainActor func drawFill(_ color: NSColor, in slot: CGRect) {
        let rect = slot.insetBy(dx: fillInset.width, dy: fillInset.height)
        let radius = fillRadius ?? min(rect.width, rect.height) / 2
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }
}

/// A button that takes the first click although the palette never becomes key, and tells the
/// palette while the pointer rests on it.
private final class PaletteButton: NSButton {
    /// Shown in the hover label.
    var name: String?

    /// Whether the button shows a setting, filled while it is on; the palette sets `state` from the
    /// setting. Any other button just acts, or opens a list, and is filled only while pressed.
    private(set) var isToggle = false

    func makeToggle() {
        setButtonType(.pushOnPushOff)
        isToggle = true
    }

    /// While the list the button opened shows, it is filled as though pressed.
    var isListOpen = false {
        didSet { needsDisplay = true }
    }

    /// While the window picker it started runs, it is filled as though pressed.
    var isPicking = false {
        didSet { needsDisplay = true }
    }

    /// Whether the pointer is on the button where it takes the mouse, as the palette was last told.
    private var isHovered = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Only inside its slot in the group and the group's rounded outline, `point` in the superview's
    /// coordinates: the group's stack, which fills the group. The slot is the alignment rect the
    /// stack lays out, `buttonSize`; the frame is taller by the symbol's alignment insets and
    /// overlaps the neighbours. The square corners outside the outline fall through to the stack,
    /// which lets a mouse-down drag the palette.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let group = superview?.bounds,
            PaletteHitShape.buttonTakes(
                point, buttonFrame: alignmentRect(forFrame: frame), group: group,
                radius: ToolbarLook.current.groupRadius)
        else { return nil }
        return super.hitTest(point)
    }

    /// The toolbar's on and pressed look (`PaletteButtonLook`), in the button's slot: the bounds are
    /// taller by the symbol's alignment insets. The colours resolve here, so an appearance or accent
    /// change shows at the next draw.
    override func draw(_ dirtyRect: NSRect) {
        let slot = convert(alignmentRect(forFrame: frame), from: superview)
        let look = PaletteButtonLook.look(
            isHighlighted: isHighlighted, isListOpen: isListOpen, isPicking: isPicking, isToggle: isToggle,
            isOn: state == .on, isEnabled: isEnabled)
        switch look.fill {
        case .none: break
        case .pressed: ToolbarLook.current.drawFill(.systemFill, in: slot)
        case .accent(let enabled):
            ToolbarLook.current.drawFill(.controlAccentColor.withAlphaComponent(enabled ? 1 : 0.5), in: slot)
        }
        let tint: NSColor =
            switch look.symbol {
            case .label: .labelColor
            case .tertiary: .tertiaryLabelColor
            case .onAccent(let enabled): NSColor(white: 0.9375, alpha: enabled ? 1 : 0.55)
            }
        // Unchanged, setting it would ask for another draw.
        if contentTintColor != tint { contentTintColor = tint }
        super.draw(dirtyRect)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(
            NSTrackingArea(
                rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                owner: self))
    }

    /// From outside the frame, so not hovered yet, even if hiding the palette sent no exit.
    override func mouseEntered(with event: NSEvent) {
        isHovered = false
        updateHover(event)
    }
    override func mouseMoved(with event: NSEvent) { updateHover(event) }

    override func mouseExited(with event: NSEvent) {
        guard isHovered else { return }
        isHovered = false
        (window as? StudioPalette)?.pointerExited(self)
    }

    /// Hovered only where the button takes the mouse: not in a square corner outside the outline.
    private func updateHover(_ event: NSEvent) {
        guard let superview else { return }
        let inside = hitTest(superview.convert(event.locationInWindow, from: nil)) != nil
        guard inside != isHovered else { return }
        isHovered = inside
        if inside {
            (window as? StudioPalette)?.pointerEntered(self)
        } else {
            (window as? StudioPalette)?.pointerExited(self)
        }
    }

    /// Off, the toolbar's disabled look (`draw(_:)`): the symbol in the tertiary label colour, a
    /// toggle's on fill kept but faded, as a disabled menu item keeps its check mark.
    override var isEnabled: Bool {
        didSet {
            // Else the cell halves the tinted symbol's alpha again, below the toolbar's.
            (cell as? NSButtonCell)?.imageDimsWhenDisabled = false
            needsDisplay = true
        }
    }

    /// A click on a button that is off does nothing, and its name stays.
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        (window as? StudioPalette)?.endHover()
        super.mouseDown(with: event)
    }
}
