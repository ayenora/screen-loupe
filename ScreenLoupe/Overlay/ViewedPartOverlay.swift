import AppKit

/// The outline of the part of the Capture Area the Viewer shows (docs/product.md, Capture Area), in
/// a click-through panel of its own just below the frame's: the frame's panel takes presses on every
/// drawn pixel, and the outline must never take one, also while it stays shown with the viewport
/// handle. It also draws the frame's line while the magnet's area is fitted to its window, so the
/// line takes no press either, and the band of the margins between that line and the captured rect,
/// which passes clicks and gestures through too. It is the app's window, so the Viewer doesn't show it.
@MainActor
final class ViewedPartOverlay: NSPanel {
    private let outline = ViewedPartView()
    private let frameLine = FrameLineView()
    private let band = MarginsBandView()
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
        let content = NSView()
        for view in [band, outline, frameLine] {
            view.autoresizingMask = [.width, .height]
            content.addSubview(view)
        }
        contentView = content
        outline.alphaValue = 0
        frameLine.isHidden = true
        band.isHidden = true
    }

    override var canBecomeKey: Bool { false }

    var style: FrameStyle? {
        get { outline.style }
        set {
            outline.style = newValue
            frameLine.style = newValue
        }
    }

    /// Covers `frame`, the frame's overlay window, with the outline of `viewedPart` clipped to
    /// `innerRect`, the captured rect, all in AppKit global coordinates, with the frame's line around
    /// `captureRect`, the frame's rect, when `drawsFrameLine`, and between the two the margins' band in
    /// `bandColor`, `nil` for none. A hidden outline isn't redrawn, and one whose part is gone fades
    /// out where it last was.
    func place(
        frame: CGRect, captureRect: CGRect, innerRect: CGRect, viewedPart: CGRect?, drawsFrameLine: Bool,
        bandColor: NSColor?
    ) {
        setFrame(frame, display: false)
        frameLine.isHidden = !drawsFrameLine
        if drawsFrameLine { frameLine.captureRect = captureRect.offsetBy(dx: -frame.minX, dy: -frame.minY) }
        band.isHidden = bandColor == nil
        if let bandColor {
            band.color = bandColor
            band.outer = captureRect.offsetBy(dx: -frame.minX, dy: -frame.minY)
            band.inner = innerRect.offsetBy(dx: -frame.minX, dy: -frame.minY)
        }
        guard isShown, let viewedPart else { return }
        outline.captureRect = innerRect.offsetBy(dx: -frame.minX, dy: -frame.minY)
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

/// The frame's line, as `CaptureOverlayView` draws it.
private final class FrameLineView: NSView {
    var captureRect: CGRect = .zero { didSet { needsDisplay = true } }
    var style: FrameStyle? { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        guard let style else { return }
        OverlayStyle.drawLine(around: captureRect, style: style, appearance: effectiveAppearance)
    }
}

/// The margins' band: `outer`, the frame's rect, less `inner`, the captured rect, filled with `color`.
private final class MarginsBandView: NSView {
    var outer: CGRect = .zero { didSet { if outer != oldValue { needsDisplay = true } } }
    var inner: CGRect = .zero { didSet { if inner != oldValue { needsDisplay = true } } }
    var color: NSColor = .clear { didSet { if color != oldValue { needsDisplay = true } } }

    override func draw(_ dirtyRect: NSRect) {
        let band = NSBezierPath(rect: outer)
        band.append(NSBezierPath(rect: inner))
        band.windingRule = .evenOdd
        color.setFill()
        band.fill()
    }
}
