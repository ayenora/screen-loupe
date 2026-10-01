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

    /// `views` one under another, or side by side, on a group's background.
    @MainActor func group(_ views: [NSView], orientation: NSUserInterfaceLayoutOrientation = .vertical) -> NSView {
        let stack = NSStackView(views: views)
        stack.orientation = orientation
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
