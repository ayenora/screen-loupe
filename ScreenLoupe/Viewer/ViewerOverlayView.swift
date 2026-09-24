import AppKit

/// Drawn over the magnified image: the crosshair on the pixel under the real cursor inside the
/// Capture Area (mockup variant A), which the capture itself doesn't show.
///
/// Only for the real cursor: when the mouse is over the Viewer, the mouse pointer already marks the
/// spot. Lines run across the whole view through that pixel, and a box outlines it; white under
/// orange reads on any content. Never takes the mouse.
final class ViewerOverlayView: NSView {
    private let zoomPan: ZoomPanController
    private let inspector: PixelInspector
    var showsCrosshair = true { didSet { needsDisplay = true } }

    private static let accent = NSColor(srgbRed: 1, green: 0.42, blue: 0, alpha: 1)

    init(zoomPan: ZoomPanController, inspector: PixelInspector) {
        self.zoomPan = zoomPan
        self.inspector = inspector
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        // The Viewer's drawable is its size in points times the window's backing scale.
        let drawableScale = window?.backingScaleFactor ?? 1
        guard showsCrosshair, let probe = inspector.probe, probe.source == .captureArea else { return }
        let placed = zoomPan.state.imageRect(
            origin: CGPoint(x: probe.x, y: probe.y), size: CGSize(width: 1, height: 1))
        let pixel = CGRect(
            x: placed.minX / drawableScale, y: placed.minY / drawableScale,
            width: placed.width / drawableScale, height: placed.height / drawableScale)
        let center = CGPoint(x: pixel.midX, y: pixel.midY)

        let lines = NSBezierPath()
        lines.move(to: CGPoint(x: bounds.minX, y: center.y))
        lines.line(to: CGPoint(x: bounds.maxX, y: center.y))
        lines.move(to: CGPoint(x: center.x, y: bounds.minY))
        lines.line(to: CGPoint(x: center.x, y: bounds.maxY))
        let box = NSBezierPath(rect: pixel.insetBy(dx: -1, dy: -1))

        NSColor.white.withAlphaComponent(0.85).setStroke()
        lines.lineWidth = 3
        lines.stroke()
        box.lineWidth = 3
        box.stroke()
        Self.accent.setStroke()
        lines.lineWidth = 1
        lines.stroke()
        box.lineWidth = 1.5
        box.stroke()
    }
}

extension NSCursor {
    /// An eyedropper with a white halo, tip at the bottom left, for picking colours in the Viewer.
    @MainActor
    static let eyedropper: NSCursor = {
        let size = NSSize(width: 22, height: 22)
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        guard
            let symbol = NSImage(systemSymbolName: "eyedropper", accessibilityDescription: "Eyedropper")?
                .withSymbolConfiguration(configuration)
        else { return .crosshair }

        func tinted(_ color: NSColor) -> NSImage {
            NSImage(size: symbol.size, flipped: false) { rect in
                symbol.draw(in: rect)
                color.set()
                rect.fill(using: .sourceAtop)
                return true
            }
        }
        let black = tinted(.black)
        let white = tinted(.white)
        let image = NSImage(size: size, flipped: false) { _ in
            let origin = CGPoint(x: 2, y: 2)
            for dx in [-1.0, 0, 1] {
                for dy in [-1.0, 0, 1] where dx != 0 || dy != 0 {
                    white.draw(
                        at: CGPoint(x: origin.x + dx, y: origin.y + dy), from: .zero, operation: .sourceOver,
                        fraction: 1)
                }
            }
            black.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        // The hot spot is measured from the image's top-left corner: the tip, bottom left.
        return NSCursor(image: image, hotSpot: NSPoint(x: 3, y: size.height - 3))
    }()
}
