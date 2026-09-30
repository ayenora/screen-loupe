import CoreGraphics

/// The hints at the bottom of the Viewer's image — how a freeze from another app happened, how to
/// get a selection for the Selection Ruler — as pills stacked upward from the bottom in the order
/// given, centred, so two showing at once never overlap. Points, y down.
enum ViewerHints {
    /// Between the lowest pill and the image's bottom, and between two pills.
    static let bottomMargin: CGFloat = 20
    static let spacing: CGFloat = 8
    /// Around a hint's text in its pill.
    static let padding = CGSize(width: 12, height: 6)

    /// A pill for text of `textSize`, on whole points.
    static func pillSize(textSize: CGSize) -> CGSize {
        CGSize(
            width: (textSize.width + 2 * padding.width).rounded(.up),
            height: (textSize.height + 2 * padding.height).rounded(.up))
    }

    /// The pills of `sizes`, the first lowest, each centred in `bounds` on whole points.
    static func rects(sizes: [CGSize], in bounds: CGRect) -> [CGRect] {
        var bottom = bounds.maxY - bottomMargin
        return sizes.map { size in
            let rect = CGRect(
                x: (bounds.midX - size.width / 2).rounded(), y: (bottom - size.height).rounded(), width: size.width,
                height: size.height)
            bottom = rect.minY - spacing
            return rect
        }
    }
}
