import AppKit

/// The Screenshot studio's palette (docs/product.md, Screenshot studio): a narrow floating strip of
/// icon buttons, dragged by the grab bar at its top and parked anywhere, apart from the frame.
///
/// A non-activating panel, so a click on it leaves the app the user works in active. AppKit shows
/// tooltips only while the app is active, so the palette names the hovered button itself, in a small
/// label beside it. Its buttons call the studio controller directly.
@MainActor
final class StudioPalette: NSPanel {
    static let width: CGFloat = 40
    private static let buttonSize = CGSize(width: 30, height: 28)
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
    var onToggleOnTop: (() -> Void)?
    var onHide: (() -> Void)?
    /// Called when a drag of the palette begins.
    var onDragStarted: (() -> Void)?
    /// Called when the user has dragged the palette to a new place.
    var onMoved: (() -> Void)?

    /// Floats above other apps' windows, below the studio's frame (`.statusBar`).
    var keepsOnTop = false {
        didSet {
            updateLevel()
            onTopButton.state = keepsOnTop ? .on : .off
        }
    }

    /// While windows are picked to leave out, the palette floats above the picker's panels, so its
    /// Leave Out Windows button can end the picking; the button is filled meanwhile.
    var isPickingWindows = false {
        didSet {
            updateLevel()
            leaveOutWindowsButton.state = isPickingWindows ? .on : .off
        }
    }

    /// While the window for One Window is picked, the palette floats above the picker's panels as
    /// well, so its One Window button can cancel it.
    var isPickingOneWindow = false {
        didSet {
            updateLevel()
            updateOneWindowButton()
        }
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

    private func updateLevel() {
        if isPickingWindows || isPickingOneWindow {
            level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        } else {
            level = keepsOnTop ? .floating : .normal
        }
    }

    /// Filled while Aspect Lock is on.
    var aspectLocked = false {
        didSet { aspectLockButton.state = aspectLocked ? .on : .off }
    }

    private let onTopButton = PaletteButton()
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

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let capture = Self.button("camera.fill", "Capture — Copy and Save", #selector(captureClicked))
        capture.isBordered = false
        capture.wantsLayer = true
        capture.layer?.backgroundColor = SettingsColor.studio.nsColor.cgColor
        capture.layer?.cornerRadius = 6
        capture.contentTintColor = .white
        Self.configure(saveButton, "square.and.arrow.down", "Save…", #selector(saveClicked))
        Self.configure(onTopButton, "pin", "Keep on Top", #selector(onTopClicked))
        onTopButton.setButtonType(.pushOnPushOff)
        onTopButton.alternateImage = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Keep on Top")
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

        let separators = (0..<3).map { _ in
            let separator = NSBox()
            separator.boxType = .separator
            separator.widthAnchor.constraint(equalToConstant: 24).isActive = true
            return separator
        }
        let grabBar = GrabBar()
        grabBar.onMoved = { [weak self] in self?.onMoved?() }
        grabBar.onDragStarted = { [weak self] in self?.onDragStarted?() }
        let stack = NSStackView(views: [
            grabBar,
            capture,
            Self.button("doc.on.doc", "Copy", #selector(copyClicked)),
            saveButton,
            separators[0],
            Self.button("arrow.up.left.and.arrow.down.right", "Size", #selector(sizeClicked)),
            aspectLockButton,
            timerButton,
            separators[1],
            backgroundButton,
            leaveOutWindowsButton,
            oneWindowButton,
            dockButton,
            pointerButton,
            separators[2],
            onTopButton,
            Self.button("eye.slash", "Hide Screenshot Studio", #selector(hideClicked)),
        ])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 5, bottom: 6, right: 5)
        for case let button as NSButton in stack.arrangedSubviews {
            button.target = self
        }
        // A group of buttons, then a separator with a little more room on each side.
        stack.setCustomSpacing(6, after: saveButton)
        stack.setCustomSpacing(6, after: separators[0])
        stack.setCustomSpacing(6, after: timerButton)
        stack.setCustomSpacing(6, after: separators[1])
        stack.setCustomSpacing(6, after: pointerButton)
        stack.setCustomSpacing(6, after: separators[2])

        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.maskImage = Self.roundedMask(radius: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            stack.widthAnchor.constraint(equalToConstant: Self.width),
        ])
        contentView = background
        setContentSize(background.fittingSize)
    }

    /// A click on a button goes to its action without first making the panel key.
    override var canBecomeKey: Bool { false }

    override func orderOut(_ sender: Any?) {
        hover(nil)
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

    /// Right of the palette, or left of it at the display's right edge, level with the button.
    private func showLabel(for button: PaletteButton) {
        hoverTimer = nil
        guard isVisible, let name = button.name else { return }
        let size = CGSize(width: OverlayStyle.labelWidth(for: name), height: OverlayMetrics.standard.labelHeight)
        let buttonFrame = convertToScreen(button.convert(button.bounds, to: nil))
        let visible = screen?.visibleFrame ?? frame
        let gap: CGFloat = 6
        var x = frame.maxX + gap
        if x + size.width > visible.maxX { x = frame.minX - gap - size.width }
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
        button.bezelStyle = .toolbar
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.imagePosition = .imageOnly
        button.name = title
        button.setAccessibilityHelp(title)
        button.action = action
        button.widthAnchor.constraint(equalToConstant: buttonSize.width).isActive = true
        button.heightAnchor.constraint(equalToConstant: buttonSize.height).isActive = true
    }

    @objc private func captureClicked() { onCapture?() }
    @objc private func copyClicked() { onCopy?() }
    @objc private func saveClicked() { onSave?() }
    @objc private func hideClicked() { onHide?() }
    @objc private func sizeClicked(_ sender: NSButton) { onSize?(sender) }

    /// Shows the setting, not the click, as Keep on Top does.
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

    /// Shows the setting, not the click: the setting sets it back.
    @objc private func onTopClicked(_ sender: NSButton) {
        sender.state = keepsOnTop ? .on : .off
        onToggleOnTop?()
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

/// A button that takes the first click although the palette never becomes key, and tells the
/// palette while the pointer rests on it.
private final class PaletteButton: NSButton {
    /// Shown in the hover label.
    var name: String?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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

/// The handle at the palette's top: dragging it moves the palette.
private final class GrabBar: NSView {
    /// Called on the first move of a drag.
    var onDragStarted: (() -> Void)?
    /// Called when a drag that moved the palette ends.
    var onMoved: (() -> Void)?
    private var dragStart: (mouse: CGPoint, origin: CGPoint)?
    private var hasDragged = false

    override var intrinsicContentSize: NSSize { NSSize(width: StudioPalette.width, height: 14) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        dragStart = (NSEvent.mouseLocation, window.frame.origin)
        hasDragged = false
        NSCursor.closedHand.push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart, let window else { return }
        if !hasDragged {
            hasDragged = true
            onDragStarted?()
        }
        let mouse = NSEvent.mouseLocation
        window.setFrameOrigin(
            CGPoint(
                x: dragStart.origin.x + mouse.x - dragStart.mouse.x, y: dragStart.origin.y + mouse.y - dragStart.mouse.y
            ))
    }

    override func mouseUp(with event: NSEvent) {
        NSCursor.pop()
        let moved = dragStart.map { $0.origin != window?.frame.origin } ?? false
        dragStart = nil
        if moved { onMoved?() }
    }

    override func draw(_ dirtyRect: NSRect) {
        let bar = CGRect(x: (bounds.width - 16) / 2, y: (bounds.height - 4) / 2, width: 16, height: 4)
        NSColor.tertiaryLabelColor.setFill()
        NSBezierPath(roundedRect: bar, xRadius: 2, yRadius: 2).fill()
    }
}
