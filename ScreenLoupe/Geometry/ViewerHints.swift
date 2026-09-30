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

/// The indicators around the Viewer's image — frozen, a delayed freeze, a recent capture shown,
/// the colour vision simulation — each a border around the image and a pill at its top centre.
/// The simulation's stacks under another one that shows, so neither covers the other: its pill
/// below the other's, its border just inside the other's. Points, y down.
enum ViewerIndicators {
    /// The pill's top when it is the only one.
    static let top: CGFloat = 12
    /// Between the other pill's bottom and the simulation's.
    static let spacing: CGFloat = 6
    static let borderWidth: CGFloat = 3

    /// The simulation's pill's top: below `otherBottom`, the bottom of another indicator's pill
    /// that shows, else at `top`.
    static func simulationTop(below otherBottom: CGFloat?) -> CGFloat {
        otherBottom.map { ($0 + spacing).rounded() } ?? top
    }

    /// How far the simulation's border sits in from the image's edge: inside another indicator's
    /// border when one shows.
    static func simulationBorderInset(otherShows: Bool) -> CGFloat {
        otherShows ? borderWidth : 0
    }
}
