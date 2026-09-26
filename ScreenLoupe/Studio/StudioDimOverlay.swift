import AppKit

/// Dims the windows left out of the studio's pictures where they lie inside its frame
/// (docs/product.md, Screenshot studio), so it is visible what the picture will miss.
///
/// A click-through panel over the frame's inside: it takes no mouse, so work in the frame goes on
/// as usual. It is the app's window, so neither a picture nor the Viewer shows it.
@MainActor
final class StudioDimOverlay: NSPanel {
    private let dimView = DimView()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        contentView = dimView
    }

    override var canBecomeKey: Bool { false }

    /// Covers `frame` (AppKit global points) and dims `rects` in it, below the window numbered
    /// `below` (the studio's frame); hides when there is nothing to dim.
    func show(_ rects: [CGRect], in frame: CGRect, below windowNumber: Int) {
        guard !rects.isEmpty else {
            orderOut(nil)
            return
        }
        setFrame(frame, display: false)
        dimView.rects = rects.map { $0.offsetBy(dx: -frame.minX, dy: -frame.minY) }
        if !isVisible { order(.below, relativeTo: windowNumber) }
    }
}

private final class DimView: NSView {
    var rects: [CGRect] = [] {
        didSet { if rects != oldValue { needsDisplay = true } }
    }

    override func draw(_ dirtyRect: NSRect) {
        // One path, so where two windows overlap the dim is the same.
        let path = NSBezierPath()
        path.windingRule = .nonZero
        rects.forEach(path.appendRect)
        NSColor.black.withAlphaComponent(0.45).setFill()
        path.fill()
    }
}
