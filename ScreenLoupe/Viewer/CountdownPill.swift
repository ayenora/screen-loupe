import AppKit

/// A countdown's dark pill: a ring that empties as the seconds run out, the seconds left in it, and
/// a text after it. Drawn in a flipped view: the delayed freeze's over the Viewer's image, and the
/// Screenshot studio's timer, smaller and in the studio's orange, beside its frame's tab.
@MainActor
struct CountdownPill {
    var ring: CGFloat
    /// Between the ring and the pill's edge.
    var inset: CGFloat
    var lineWidth: CGFloat
    var color: NSColor
    var textAttributes: [NSAttributedString.Key: Any]
    var digitAttributes: [NSAttributedString.Key: Any]

    static let freeze = CountdownPill(
        ring: 26, inset: 6, lineWidth: 2.5, color: .systemBlue, textAttributes: FrozenIndicatorView.attributes,
        digitAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold), .foregroundColor: NSColor.white,
        ])

    static let studio = CountdownPill(
        ring: 20, inset: 4, lineWidth: 2, color: SettingsColor.studio.nsColor,
        textAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.white],
        digitAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold), .foregroundColor: NSColor.white,
        ])

    /// Between the ring and the text, and after the text.
    private static let textGap: CGFloat = 8
    private static let trailing: CGFloat = 14

    /// The pill's width before rounding up, to centre it by.
    func exactWidth(for text: String) -> CGFloat {
        inset + ring + Self.textGap + (text as NSString).size(withAttributes: textAttributes).width + Self.trailing
    }

    func size(for text: String) -> CGSize {
        CGSize(width: exactWidth(for: text).rounded(.up), height: ring + 2 * inset)
    }

    /// `pill` is `size(for: text)` placed; `fraction` of the ring is left.
    func draw(_ text: String, seconds: Int, fraction: CGFloat, in pill: CGRect) {
        FrozenIndicatorView.darkFill.setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()

        let center = CGPoint(x: pill.minX + inset + ring / 2, y: pill.midY)
        let radius = (ring - lineWidth) / 2
        let track = NSBezierPath(
            ovalIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        track.lineWidth = lineWidth
        color.withAlphaComponent(0.25).setStroke()
        track.stroke()
        // Flipped view: growing angles run clockwise, from the top.
        let arc = NSBezierPath()
        arc.appendArc(
            withCenter: center, radius: radius, startAngle: -90, endAngle: -90 + 360 * fraction, clockwise: false)
        arc.lineWidth = lineWidth
        color.setStroke()
        arc.stroke()
        let digits = "\(seconds)" as NSString
        let digitSize = digits.size(withAttributes: digitAttributes)
        digits.draw(
            at: CGPoint(x: (center.x - digitSize.width / 2).rounded(), y: (center.y - digitSize.height / 2).rounded()),
            withAttributes: digitAttributes)
        let textSize = (text as NSString).size(withAttributes: textAttributes)
        (text as NSString).draw(
            at: CGPoint(x: pill.minX + inset + ring + Self.textGap, y: (pill.midY - textSize.height / 2).rounded()),
            withAttributes: textAttributes)
    }
}
