import AppKit

/// The Viewer toolbar's look as `NSToolbar` draws it on this macOS. From macOS 26 its items sit
/// flush in Liquid Glass capsules as tall as the bar, 36 pt, 8 pt apart around a space, and a pressed
/// button shows a grey 30 × 28 pt capsule. Before, the items sit on the titlebar's material, and
/// a pressed button shows a rounded grey rect. A toggle that is on, in an active app, fills the same
/// shape with the accent colour under a near-white symbol. Drawn by the studio's palette and the
/// Viewer's zoom presets (`PaletteButton`); also the size and pressed shape of Recent Captures'
/// camera button.
struct ToolbarLook {
    let isGlass: Bool
    let buttonSize: CGSize
    let fillInset: CGSize
    /// `nil` for a capsule.
    let fillRadius: CGFloat?
    let groupRadius: CGFloat
    let groupSpacing: CGFloat = 8
    /// The height of a button's on or pressed fill.
    var fillHeight: CGFloat { buttonSize.height - 2 * fillInset.height }
    /// A ▾ button's view beside the button whose menu it opens: as wide as its highlight
    /// (`PaletteMenuButton`).
    var menuButtonWidth: CGFloat { PaletteMenuButton.fillWidth(fillHeight: fillHeight) }
    /// Marks the stack `group` makes, so a button in a row within it finds the group's outline.
    static let groupIdentifier = NSUserInterfaceItemIdentifier("toolbarGroup")

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

    /// A rounded rectangle's corners for a group holding a text field rather than buttons: a large
    /// rounded text field's outer border, 8 pt (measured on macOS 27: 7 pt inside, 8 pt for its
    /// border), and the groups' radius before macOS 26.
    static let fieldGroupRadius: CGFloat = 8

    /// The width of the studio's palette and of the Viewer's floating zoom panel, so the two stand
    /// alike: the widest row, a button and its ▾ (`PaletteMenuButton.rowWidth`), and the margins
    /// (`StudioPlacement.paletteWidth`): 74 pt from macOS 26, 68 pt before.
    var paletteWidth: CGFloat {
        StudioPlacement.paletteWidth(
            buttonWidth: PaletteMenuButton.rowWidth(buttonWidth: buttonSize.width, fillHeight: fillHeight))
    }

    /// `views` one under another, or side by side, on a group's background: a capsule from macOS
    /// 26, as the toolbar's items are, or with `cornerRadius` (`fieldGroupRadius` for a field).
    @MainActor func group(
        _ views: [NSView], orientation: NSUserInterfaceLayoutOrientation = .vertical, cornerRadius: CGFloat? = nil
    ) -> NSView {
        let stack = NSStackView(views: views)
        stack.orientation = orientation
        // A wider row among them, the others centred on it.
        stack.alignment = orientation == .vertical ? .centerX : .centerY
        stack.spacing = 0
        stack.identifier = Self.groupIdentifier
        if #available(macOS 26.0, *), isGlass {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius ?? groupRadius
            glass.contentView = stack
            return glass
        }
        let background = NSVisualEffectView()
        background.material = .titlebar
        background.blendingMode = .behindWindow
        background.state = .active
        background.maskImage = StudioPalette.roundedMask(radius: cornerRadius ?? groupRadius)
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

    /// A ▾ button's pressed fill, centred in its view's `slot`: as tall as a button's fill and
    /// `PaletteMenuButton.fillWidth` wide — from macOS 26 a circle, as the toolbar's ▾ shows it;
    /// before, a rounded rect with the buttons' corners.
    @MainActor func drawMenuFill(_ color: NSColor, in slot: CGRect) {
        let width = PaletteMenuButton.fillWidth(fillHeight: fillHeight)
        let rect = CGRect(x: slot.midX - width / 2, y: slot.midY - fillHeight / 2, width: width, height: fillHeight)
        let radius = fillRadius ?? fillHeight / 2
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }

    /// The on or pressed fill of a button whose slot is `slot`.
    @MainActor func drawFill(_ color: NSColor, in slot: CGRect) {
        let rect = slot.insetBy(dx: fillInset.width, dy: fillInset.height)
        let radius = fillRadius ?? min(rect.width, rect.height) / 2
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }
}
