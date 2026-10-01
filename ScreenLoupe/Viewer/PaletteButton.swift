import AppKit

/// The window a `PaletteButton` tells while the pointer rests on one of its buttons: the studio's
/// palette, which names them itself (`ButtonNameLabel`).
@MainActor
protocol PaletteButtonHost: AnyObject {
    func pointerEntered(_ button: PaletteButton)
    func pointerExited(_ button: PaletteButton)
    /// A click on a button: its name goes.
    func endHover()
}

/// A button in the toolbar's look (`ToolbarLook`, `PaletteButtonLook`), in a group of the studio's
/// palette or of the Viewer's zoom presets: it takes the first click, even in a panel that isn't key,
/// never makes a panel key or takes the focus, and tells its window, when that is a
/// `PaletteButtonHost`, while the pointer rests on it. It shows a symbol, or a short text in its
/// place (the zoom presets), tinted as the look says.
final class PaletteButton: NSButton {
    /// Shown in the hover label.
    var name: String?

    /// A borderless button in a `buttonSize` slot, named `name`, showing `symbol` at the scale
    /// `NSToolbar` gives a `.toolbar`-bezel button's image.
    func show(symbol: String, name: String) {
        setUp(name: name)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: name)
        imagePosition = .imageOnly
        symbolConfiguration = NSImage.SymbolConfiguration(scale: .large)
        imageScaling = .scaleNone
    }

    /// As `show(symbol:name:)`, with `text` in place of a symbol, in the system font's regular size,
    /// tinted as a symbol is. Its window is active, so `name` is its tooltip.
    func show(text: String, name: String) {
        setUp(name: name)
        title = text
        imagePosition = .noImage
        font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        toolTip = name
        setAccessibilityLabel(name)
    }

    private func setUp(name: String) {
        isBordered = false
        contentTintColor = .labelColor
        refusesFirstResponder = true
        self.name = name
        let size = ToolbarLook.current.buttonSize
        widthAnchor.constraint(equalToConstant: size.width).isActive = true
        heightAnchor.constraint(equalToConstant: size.height).isActive = true
    }

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

    /// Whether the pointer is on the button where it takes the mouse, as the host was last told.
    private var isHovered = false

    /// The toolbar's near-white symbol on the accent fill.
    private static let onAccentWhite: CGFloat = 0.9375
    /// A disabled toggle that is on, faded as the toolbar's: its accent fill, and its symbol.
    private static let disabledAccentAlpha: CGFloat = 0.5
    private static let disabledOnAccentAlpha: CGFloat = 0.55

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// A click leaves the key window as it is, with Full Keyboard Access on too: the zoom panel's
    /// buttons keep the keys going to the Viewer's image.
    override var needsPanelToBecomeKey: Bool { false }

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
            ToolbarLook.current.drawFill(
                .controlAccentColor.withAlphaComponent(enabled ? 1 : Self.disabledAccentAlpha), in: slot)
        }
        let tint: NSColor =
            switch look.symbol {
            case .label: .labelColor
            case .tertiary: .tertiaryLabelColor
            case .onAccent(let enabled):
                NSColor(white: Self.onAccentWhite, alpha: enabled ? 1 : Self.disabledOnAccentAlpha)
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
        (window as? PaletteButtonHost)?.pointerExited(self)
    }

    /// Hovered only where the button takes the mouse: not in a square corner outside the outline.
    private func updateHover(_ event: NSEvent) {
        guard let superview else { return }
        let inside = hitTest(superview.convert(event.locationInWindow, from: nil)) != nil
        guard inside != isHovered else { return }
        isHovered = inside
        if inside {
            (window as? PaletteButtonHost)?.pointerEntered(self)
        } else {
            (window as? PaletteButtonHost)?.pointerExited(self)
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
        (window as? PaletteButtonHost)?.endHover()
        super.mouseDown(with: event)
    }
}
