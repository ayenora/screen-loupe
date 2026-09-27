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
    var onToggleAspectLock: (() -> Void)?
    /// Called with the Timer button, to open the delays beside it.
    var onTimer: ((NSView) -> Void)?
    /// Called with the Background button, to open the backgrounds beside it.
    var onBackground: ((NSView) -> Void)?
    var onToggleLeaveOutWindows: (() -> Void)?
    var onToggleOneWindow: (() -> Void)?
    var onToggleLeaveOutDock: (() -> Void)?
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

    /// While windows are picked to leave out, the Leave Out Windows button is filled; being above
    /// the picker's panels, it can end the picking.
    var isPickingWindows = false {
        didSet { leaveOutWindowsButton.state = isPickingWindows ? .on : .off }
    }

    /// While the window for One Window is picked; the One Window button, above the picker's panels,
    /// can cancel it.
    var isPickingOneWindow = false {
        didSet { updateOneWindowButton() }
    }

    /// Whether One Window has a window. Its pictures take the window alone, so the buttons for what
    /// else a picture holds are off meanwhile, showing their settings.
    var hasOneWindow = false {
        didSet {
            updateOneWindowButton()
            for button in [leaveOutWindowsButton, dockButton, pointerButton] { button.isEnabled = !hasOneWindow }
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

    /// Filled while the Dock is left out.
    var leavesOutDock = false {
        didSet { dockButton.state = leavesOutDock ? .on : .off }
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

    /// The Size, Timer or Background button whose list is open: it shows pressed until the list
    /// closes. Set by the studio when it opens a list, cleared when the list is ordered out.
    var openListButton: NSView? {
        didSet {
            guard openListButton !== oldValue else { return }
            (oldValue as? PaletteButton)?.isListOpen = false
            (openListButton as? PaletteButton)?.isListOpen = true
        }
    }

    private let aspectLockButton = PaletteButton()
    private let backgroundButton = PaletteButton()
    private let leaveOutWindowsButton = PaletteButton()
    private let oneWindowButton = PaletteButton()
    private let dockButton = PaletteButton()
    private let timerButton = PaletteButton()
    private let pointerButton = PaletteButton()
    private let saveButton = PaletteButton()
    private let hoverLabel = HoverLabelWindow()
    private var hoverTimer: Timer?
    /// The button the pointer last entered, until it leaves it or clicks.
    private var hoveredButton: PaletteButton?
    /// When a shown name last went as the pointer left its button (`HoverLabelDelay`); `nil` after
    /// a click and while hidden.
    private var labelHiddenAt: TimeInterval?
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
        Self.configure(aspectLockButton, "aspectratio", "Aspect Lock", #selector(aspectLockClicked))
        aspectLockButton.makeToggle()
        aspectLockButton.alternateImage = NSImage(
            systemSymbolName: "aspectratio.fill", accessibilityDescription: "Aspect Lock")
        Self.configure(
            backgroundButton, "square.3.layers.3d.bottom.filled", "Background", #selector(backgroundClicked))
        backgroundButton.makeToggle()
        Self.configure(
            leaveOutWindowsButton, "rectangle.on.rectangle.slash", "Leave Out Windows",
            #selector(leaveOutWindowsClicked))
        leaveOutWindowsButton.makeToggle()
        leaveOutWindowsButton.alternateImage = NSImage(
            systemSymbolName: "rectangle.on.rectangle.slash.fill", accessibilityDescription: "Leave Out Windows")
        Self.configure(oneWindowButton, "macwindow", "One Window", #selector(oneWindowClicked))
        oneWindowButton.makeToggle()
        Self.configure(dockButton, "dock.rectangle", "Leave Out the Dock", #selector(dockClicked))
        dockButton.makeToggle()
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
                aspectLockButton,
                timerButton,
            ],
            [backgroundButton, leaveOutWindowsButton, oneWindowButton, dockButton, pointerButton],
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
                    self.aspectLockButton, self.timerButton, self.backgroundButton, self.leaveOutWindowsButton,
                    self.oneWindowButton, self.dockButton, self.pointerButton,
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
    /// from a named button (`HoverLabelDelay`).
    fileprivate func pointerEntered(_ button: PaletteButton) {
        hideLabel()
        hoveredButton = button
        let delay = HoverLabelDelay.delay(at: ProcessInfo.processInfo.systemUptime, lastHidden: labelHiddenAt)
        guard delay > 0 else {
            showLabel(for: button)
            return
        }
        hoverTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.showLabel(for: button) }
        }
    }

    /// Buttons in a group touch, so the next one's enter comes before this one's exit: an exit
    /// from a button the pointer has already left for another changes nothing.
    fileprivate func pointerExited(_ button: PaletteButton) {
        guard hoveredButton === button else { return }
        hoveredButton = nil
        hideLabel()
    }

    /// A click or hiding: the name goes, and the next button waits the full rest.
    fileprivate func endHover() {
        hoveredButton = nil
        hideLabel()
        labelHiddenAt = nil
    }

    private func hideLabel() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        guard hoverLabel.isVisible else { return }
        removeChildWindow(hoverLabel)
        hoverLabel.orderOut(nil)
        labelHiddenAt = ProcessInfo.processInfo.systemUptime
    }

    /// Beside the palette on its side away from the studio's frame (`StudioPlacement.hoverLabelX`),
    /// level with the button.
    private func showLabel(for button: PaletteButton) {
        hoverTimer = nil
        guard isVisible, hoveredButton === button, let name = button.name else { return }
        let size = CGSize(width: OverlayStyle.labelWidth(for: name), height: OverlayMetrics.standard.labelHeight)
        let buttonFrame = convertToScreen(button.convert(button.bounds, to: nil))
        let visible = screen?.visibleFrame ?? frame
        let x = StudioPlacement.hoverLabelX(width: size.width, beside: frame, frame: studioFrame?(), in: visible)
        // At the palette's level, so it also shows above the window picker's panels.
        hoverLabel.level = level
        hoverLabel.show(
            name, in: CGRect(origin: CGPoint(x: x, y: (buttonFrame.midY - size.height / 2).rounded()), size: size))
        addChildWindow(hoverLabel, ordered: .above)
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

    /// Shows whether windows are being picked, not the click.
    @objc private func leaveOutWindowsClicked(_ sender: NSButton) {
        sender.state = isPickingWindows ? .on : .off
        onToggleLeaveOutWindows?()
    }

    /// Shows the mode, not the click.
    @objc private func oneWindowClicked(_ sender: NSButton) {
        updateOneWindowButton()
        onToggleOneWindow?()
    }

    /// Shows the setting, not the click.
    @objc private func dockClicked(_ sender: NSButton) {
        sender.state = leavesOutDock ? .on : .off
        onToggleLeaveOutDock?()
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

    /// The toolbar's on and pressed look, in the button's slot: the bounds are taller by the
    /// symbol's alignment insets. Pressed, or with its list open, a grey fill under the label-coloured
    /// symbol; a toggle that is on, the accent colour under a near-white symbol, both faded while the
    /// button is off, as the toolbar's are. A momentary button's `state` flips on every click too,
    /// though AppKit doesn't show it: only a toggle's is drawn. The colours resolve here, so an
    /// appearance or accent change shows at the next draw.
    override func draw(_ dirtyRect: NSRect) {
        let slot = convert(alignmentRect(forFrame: frame), from: superview)
        let tint: NSColor
        if isHighlighted || isListOpen {
            ToolbarLook.current.drawFill(.systemFill, in: slot)
            tint = isEnabled ? .labelColor : .tertiaryLabelColor
        } else if isToggle && state == .on {
            ToolbarLook.current.drawFill(.controlAccentColor.withAlphaComponent(isEnabled ? 1 : 0.5), in: slot)
            tint = NSColor(white: 0.9375, alpha: isEnabled ? 1 : 0.55)
        } else {
            tint = isEnabled ? .labelColor : .tertiaryLabelColor
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

/// The name of the hovered button: a small label in the look of the frame's at-rest size label.
private final class HoverLabelWindow: NSPanel {
    private let label = SizeLabelView()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        contentView = label
    }

    func show(_ text: String, in rect: CGRect) {
        label.text = text
        setFrame(rect, display: true)
    }
}
