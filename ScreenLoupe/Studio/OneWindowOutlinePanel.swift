import AppKit

/// The green outline around the window One Window captures, with its app's name (docs/product.md,
/// Screenshot studio; `OneWindowOutline`): click-through, never key, not in ⌘Tab or the Window
/// menu, at the frames' level so it shows over the window. It is the app's window, so no capture
/// and not the Viewer shows it.
@MainActor
final class OneWindowOutlinePanel: NSPanel {
    /// The app's green preset, apart from the studio's orange and the Capture Area's colour.
    static let color = SettingsColor.green

    private let lineView = OutlineLineView()
    private let label = SizeLabelView()
    private var shown: (outline: OneWindowOutline, text: String)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = NSWindow.Level(rawValue: WindowLevels.frames)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        let content = NSView()
        content.addSubview(lineView)
        content.addSubview(label)
        contentView = content
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Outlines a window at `window`, in AppKit global coordinates, named `appName`, with a line of
    /// `lineWidth` points, the label kept on `screen`. Moves only when something changed.
    func show(around window: CGRect, appName: String, lineWidth: CGFloat, screen: CGRect) {
        let labelSize = CGSize(
            width: OverlayStyle.labelWidth(for: appName), height: OverlayMetrics.standard.labelHeight)
        let outline = OneWindowOutline(window: window, lineWidth: lineWidth, labelSize: labelSize, screen: screen)
        if shown?.outline != outline || shown?.text != appName {
            shown = (outline, appName)
            setFrame(outline.panel, display: false)
            let origin = outline.panel.origin
            lineView.frame = CGRect(origin: .zero, size: outline.panel.size)
            lineView.line = outline.line.offsetBy(dx: -origin.x, dy: -origin.y)
            lineView.lineWidth = lineWidth
            label.frame = outline.label.offsetBy(dx: -origin.x, dy: -origin.y)
            label.text = appName
        }
        if !isVisible { orderFrontRegardless() }
    }

    func hide() {
        orderOut(nil)
        shown = nil
    }
}

/// The line in the green, with the frame's halo outside it.
private final class OutlineLineView: NSView {
    /// The line's outer edge; the line is drawn inside it, the halo outside.
    var line: CGRect = .zero { didSet { needsDisplay = true } }
    var lineWidth: CGFloat = 1 { didSet { needsDisplay = true } }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let halo = NSBezierPath(rect: line.insetBy(dx: -OneWindowOutline.halo / 2, dy: -OneWindowOutline.halo / 2))
        halo.lineWidth = OneWindowOutline.halo
        OverlayStyle.halo(for: effectiveAppearance).setStroke()
        halo.stroke()
        let path = NSBezierPath(rect: line.insetBy(dx: lineWidth / 2, dy: lineWidth / 2))
        path.lineWidth = lineWidth
        OneWindowOutlinePanel.color.nsColor.setStroke()
        path.stroke()
    }
}
