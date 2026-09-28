import AppKit

/// The outline of the part of the Capture Area the Viewer shows (docs/product.md, Capture Area), in
/// a click-through panel of its own just below the frame's: the frame's panel takes presses on every
/// drawn pixel, and the outline must never take one, also while it stays shown with the viewport
/// handle. It is the app's window, so the Viewer doesn't show it.
@MainActor
final class ViewedPartOverlay: NSPanel {
    private let outline = ViewedPartView()
    private var isShown = false

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
        contentView = outline
        outline.alphaValue = 0
    }

    override var canBecomeKey: Bool { false }

    var style: FrameStyle? {
        get { outline.style }
        set { outline.style = newValue }
    }

    /// Covers `frame`, the frame's overlay window, with the outline of `viewedPart` clipped to
    /// `captureRect`, all in AppKit global coordinates. A hidden outline isn't redrawn, and one whose
    /// part is gone fades out where it last was.
    func place(frame: CGRect, captureRect: CGRect, viewedPart: CGRect?) {
        setFrame(frame, display: false)
        guard isShown, let viewedPart else { return }
        outline.captureRect = captureRect.offsetBy(dx: -frame.minX, dy: -frame.minY)
        outline.viewedRect = viewedPart.offsetBy(dx: -frame.minX, dy: -frame.minY)
    }

    /// Fades the outline in or out; `place` then draws it where it is.
    func setShown(_ shown: Bool) {
        guard shown != isShown else { return }
        isShown = shown
        NSAnimationContext.runAnimationGroup { context in
            context.duration = OverlayStyle.revealDuration
            outline.animator().alphaValue = shown ? 1 : 0
        }
    }
}

/// A 1 pt dashed line in the accent with the line's halo, inside the captured rect so it never
/// covers the frame's line.
private final class ViewedPartView: NSView {
    var captureRect: CGRect = .zero { didSet { needsDisplay = true } }
    var viewedRect: CGRect? { didSet { needsDisplay = true } }
    var style: FrameStyle? { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        guard let style, let viewedRect else { return }
        NSBezierPath(rect: captureRect).setClip()
        let rect = viewedRect.insetBy(dx: 0.5, dy: 0.5)
        let dashes: [CGFloat] = [4, 3]
        let halo = NSBezierPath(rect: rect)
        halo.lineWidth = 3
        halo.setLineDash(dashes, count: dashes.count, phase: 0)
        OverlayStyle.halo(for: effectiveAppearance).setStroke()
        halo.stroke()
        let line = NSBezierPath(rect: rect)
        line.lineWidth = 1
        line.setLineDash(dashes, count: dashes.count, phase: 0)
        style.accent.setStroke()
        line.stroke()
    }
}
