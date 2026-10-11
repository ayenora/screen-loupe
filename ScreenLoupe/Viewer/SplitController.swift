import AppKit

/// The split view's line over the Viewer: which split shows, the line's place, kept in the settings
/// as a fraction of the Viewer's width (`SplitLine`), the mouse on it, and how it is drawn — over
/// the image, and into Copy View. Points here are drawable pixels, y down, as in `ZoomPanState`.
@MainActor
final class SplitController {
    /// The split shown, or `nil`: the line shows and takes the mouse only while there is one.
    var kind: SplitKind? {
        didSet { if kind != oldValue { changed() } }
    }

    /// Off while the eyedropper, the Select tool or Copy Text has the mouse: they take every press.
    var takesMouse = true

    /// The line's place, 0 at the Viewer's left edge, 1 at its right.
    private(set) var position: Double

    private let settings: SettingsStore
    private let zoomPan: ZoomPanController
    private var observers: [() -> Void] = []
    private var drag: (startPosition: Double, startX: CGFloat)?

    init(settings: SettingsStore, zoomPan: ZoomPanController) {
        self.settings = settings
        self.zoomPan = zoomPan
        position = SplitLine.clamped(settings.settings.splitPosition)
    }

    /// Calls `observer` after every change of the split shown or of the line's place.
    func observe(_ observer: @escaping () -> Void) {
        observers.append(observer)
    }

    private func changed() {
        for observer in observers { observer() }
    }

    /// The split and the line's place, for the renderer; `nil` while none shows.
    var shown: (kind: SplitKind, position: Double)? {
        kind.map { ($0, position) }
    }

    // MARK: The mouse

    /// Whether a press at `point` takes the line (`SplitLine.hits`).
    func hits(_ point: CGPoint, scale: CGFloat) -> Bool {
        guard kind != nil, takesMouse else { return false }
        let viewport = zoomPan.state.viewportSize
        return SplitLine.hits(
            point, lineX: SplitLine.x(position: position, width: viewport.width), height: viewport.height,
            scale: scale)
    }

    /// Takes a press on the line or its knob.
    func press(at point: CGPoint, scale: CGFloat) -> Bool {
        guard hits(point, scale: scale) else { return false }
        drag = (position, point.x)
        return true
    }

    var isDragging: Bool { drag != nil }

    func drag(to point: CGPoint) {
        guard let drag else { return }
        let next = SplitLine.dragged(
            from: drag.startPosition, startX: drag.startX, to: point.x, width: zoomPan.state.viewportSize.width)
        guard next != position else { return }
        position = next
        changed()
    }

    /// Keeps the place the drag left the line at.
    func endDrag() {
        drag = nil
        settings.update { [position] in $0.splitPosition = position }
    }

    static let cursor = NSCursor.resizeLeftRight

    // MARK: Drawing

    private static let labelAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.white,
    ]

    /// The line at `x` over `bounds`' whole height — white on a dark halo, as the ruler is drawn —
    /// with the knob at mid-height when `knob`, and `kind`'s side labels at `labelsTop`; into the
    /// current graphics context, in points, y down.
    static func draw(_ kind: SplitKind, x: CGFloat, in bounds: CGRect, labelsTop: CGFloat, knob: Bool) {
        let line = NSBezierPath()
        line.move(to: CGPoint(x: x, y: bounds.minY))
        line.line(to: CGPoint(x: x, y: bounds.maxY))
        NSColor.black.withAlphaComponent(0.45).setStroke()
        line.lineWidth = 3.5
        line.stroke()
        NSColor.white.setStroke()
        line.lineWidth = 1.5
        line.stroke()
        if knob { drawKnob(at: SplitLine.knobCenter(lineX: x, height: bounds.height)) }

        let texts = kind.labels
        let sizes = [texts.left, texts.right].map {
            SplitLine.labelSize(textSize: ($0 as NSString).size(withAttributes: labelAttributes))
        }
        let rects = SplitLine.labelRects(
            left: sizes[0], right: sizes[1], lineX: x, width: bounds.width, top: labelsTop)
        for (text, rect) in [(texts.left, rects.left), (texts.right, rects.right)] {
            guard let rect else { continue }
            NSColor.black.withAlphaComponent(0.68).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
            let size = (text as NSString).size(withAttributes: labelAttributes)
            (text as NSString).draw(
                at: CGPoint(x: rect.minX + SplitLine.labelPadding, y: rect.minY + ((rect.height - size.height) / 2)),
                withAttributes: labelAttributes)
        }
    }

    /// A white disc with ◀▶ in it, lifted by a soft shadow.
    private static func drawKnob(at center: CGPoint) {
        let radius = SplitLine.knobRadius
        let disc = NSBezierPath(
            ovalIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 3
        // y down: the shadow falls below the disc.
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
        NSColor.white.setFill()
        disc.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.black.withAlphaComponent(0.18).setStroke()
        disc.lineWidth = 1
        disc.stroke()
        let arrows = NSBezierPath()
        for side: CGFloat in [-1, 1] {
            arrows.move(to: CGPoint(x: center.x + 9 * side, y: center.y))
            arrows.line(to: CGPoint(x: center.x + 3 * side, y: center.y - 4.5))
            arrows.line(to: CGPoint(x: center.x + 3 * side, y: center.y + 4.5))
            arrows.close()
        }
        NSColor(srgbRed: 44 / 255, green: 44 / 255, blue: 46 / 255, alpha: 1).setFill()
        arrows.fill()
    }

    /// `image`, Copy View's, with the line at `x` (its pixels) and the side labels at the top, no
    /// knob; `scale` pixels per point. As it is when the line falls outside it (`SplitLine.isInCopy`).
    static func drawn(on image: CGImage, kind: SplitKind, x: CGFloat, scale: CGFloat) -> CGImage {
        let width = image.width
        let height = image.height
        guard SplitLine.isInCopy(x: x, width: CGFloat(width)), scale > 0,
            let space = image.colorSpace,
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return image }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // Points, y down, as over the Viewer.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        draw(
            kind, x: x / scale,
            in: CGRect(x: 0, y: 0, width: CGFloat(width) / scale, height: CGFloat(height) / scale),
            labelsTop: SplitLine.labelTop, knob: false)
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage() ?? image
    }
}
