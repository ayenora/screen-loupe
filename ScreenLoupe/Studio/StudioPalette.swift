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
    /// How long the pointer rests on a button before its name shows.
    private static let hoverDelay: TimeInterval = 0.5

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

    /// Whether One Window has a window.
    var hasOneWindow = false {
        didSet { updateOneWindowButton() }
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
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        tabbingMode = .disallowed
        // After the style: a utility panel sets itself floating.
        level = NSWindow.Level(rawValue: WindowLevels.studioPalette)
        // Over a full-screen app's Space too.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        Self.configure(saveButton, "square.and.arrow.down", "Save…", #selector(saveClicked))
        Self.configure(aspectLockButton, "aspectratio", "Aspect Lock", #selector(aspectLockClicked))
        aspectLockButton.setButtonType(.pushOnPushOff)
        aspectLockButton.alternateImage = NSImage(
            systemSymbolName: "aspectratio.fill", accessibilityDescription: "Aspect Lock")
        Self.configure(
            backgroundButton, "square.3.layers.3d.bottom.filled", "Background", #selector(backgroundClicked))
        backgroundButton.setButtonType(.pushOnPushOff)
        Self.configure(
            leaveOutWindowsButton, "rectangle.on.rectangle.slash", "Leave Out Windows",
            #selector(leaveOutWindowsClicked))
        leaveOutWindowsButton.setButtonType(.pushOnPushOff)
        leaveOutWindowsButton.alternateImage = NSImage(
            systemSymbolName: "rectangle.on.rectangle.slash.fill", accessibilityDescription: "Leave Out Windows")
        Self.configure(oneWindowButton, "macwindow", "One Window", #selector(oneWindowClicked))
        oneWindowButton.setButtonType(.pushOnPushOff)
        Self.configure(dockButton, "dock.rectangle", "Leave Out the Dock", #selector(dockClicked))
        dockButton.setButtonType(.pushOnPushOff)
        Self.configure(timerButton, "timer", "Timer", #selector(timerClicked))
        timerButton.setButtonType(.pushOnPushOff)
        Self.configure(pointerButton, "cursorarrow", "Include the Pointer", #selector(pointerClicked))
        pointerButton.setButtonType(.pushOnPushOff)

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
    }

    /// A click on a button goes to its action without first making the panel key.
    override var canBecomeKey: Bool { false }

    /// The close button hides the studio; the palette stays, to be shown again. The button's action
    /// calls `close()` directly, not `performClose(_:)`.
    override func close() { onHide?() }

    override func orderOut(_ sender: Any?) {
        hover(nil)
        isDragged = false
        super.orderOut(sender)
    }

    // MARK: Hover label

    /// Names `button` beside the palette after a short rest, or hides the name when `nil`.
    fileprivate func hover(_ button: PaletteButton?) {
        hoverTimer?.invalidate()
        hoverTimer = nil
        if hoverLabel.isVisible {
            removeChildWindow(hoverLabel)
            hoverLabel.orderOut(nil)
        }
        guard let button else { return }
        hoverTimer = Timer.scheduledTimer(withTimeInterval: Self.hoverDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.showLabel(for: button) }
        }
    }

    /// Beside the palette on its side away from the studio's frame (`StudioPlacement.hoverLabelX`),
    /// level with the button.
    private func showLabel(for button: PaletteButton) {
        hoverTimer = nil
        guard isVisible, let name = button.name else { return }
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
/// flush in Liquid Glass capsules as tall as the bar, 36 pt, 8 pt apart around a space, and a toggle
/// that is on shows a `systemFill` capsule inset 4 to 5 pt. Before, the items sit on the titlebar's
/// material, and a toggle that is on shows a rounded `systemFill` rect.
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
                isGlass: true, buttonSize: CGSize(width: 36, height: 36), fillInset: CGSize(width: 5, height: 4),
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

    /// The on or pressed fill of a button with `bounds`.
    @MainActor func drawFill(in bounds: CGRect) {
        let rect = bounds.insetBy(dx: fillInset.width, dy: fillInset.height)
        let radius = fillRadius ?? min(rect.width, rect.height) / 2
        NSColor.systemFill.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }
}

/// A button that takes the first click although the palette never becomes key, and tells the
/// palette while the pointer rests on it.
private final class PaletteButton: NSButton {
    /// Shown in the hover label.
    var name: String?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The toolbar's on and pressed look, under the symbol.
    override func draw(_ dirtyRect: NSRect) {
        if state == .on || isHighlighted { ToolbarLook.current.drawFill(in: bounds) }
        super.draw(dirtyRect)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(
            NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { (window as? StudioPalette)?.hover(self) }
    override func mouseExited(with event: NSEvent) { (window as? StudioPalette)?.hover(nil) }

    override func mouseDown(with event: NSEvent) {
        (window as? StudioPalette)?.hover(nil)
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
