import CoreGraphics

/// Which split the Viewer shows, and what its two sides are called: a reference layer in Split
/// (the layer left of the line, the live image right of it), or the colour vision split (normal
/// vision left, the simulation of `mode` right).
enum SplitKind: Equatable, Sendable {
    case reference
    /// The simulated mode's name, as its menu item has it.
    case vision(String)

    /// The side labels at the line's top: left, then right.
    var labels: (left: String, right: String) {
        switch self {
        case .reference: ("Reference", "Live")
        case .vision(let mode): ("Normal", mode)
        }
    }

    /// The split shown: the vision split while it is on, else a reference layer's in Split while
    /// one shows (visible, with the References panel open). Turning either on turns the other off
    /// (`ReferenceStack.endSplit`, `ColorVisionChoice.withoutSplit`), so both are never on at once;
    /// if they were, the vision split, which covers the whole scene, would show.
    static func shown(visionSplit mode: String?, referenceSplit: Bool) -> SplitKind? {
        if let mode { return .vision(mode) }
        return referenceSplit ? .reference : nil
    }
}

/// The split view's vertical line over the Viewer: its place, kept as a fraction of the Viewer's
/// width so panning slides the picture under it and a window resize keeps the proportion; where a
/// press takes it; where its side labels go; and what of it a copy of the view shows. Lengths are
/// points unless a function says otherwise; y down.
enum SplitLine {
    /// The line's place the first time: the middle.
    static let defaultPosition = 0.5
    /// How close to the line a press still takes it, as the ruler's line.
    static let reach: CGFloat = 5
    /// The round knob at the line's mid-height.
    static let knobRadius: CGFloat = 13
    /// Between the line and a side label.
    static let labelGap: CGFloat = 8
    /// The least a label keeps from the Viewer's edges; one that would come closer is left out.
    static let labelMargin: CGFloat = 4
    /// The labels' top with no indicator's pill at the Viewer's top.
    static let labelTop: CGFloat = 8
    /// A label's height, and the space each side of its text.
    static let labelHeight: CGFloat = 18
    static let labelPadding: CGFloat = 6

    /// `position` within the Viewer's edges, 0...1; a value that isn't a number is the default.
    static func clamped(_ position: Double) -> Double {
        position.isFinite ? min(max(position, 0), 1) : defaultPosition
    }

    /// The line's x in a viewport `width` wide, in the same units.
    static func x(position: Double, width: CGFloat) -> CGFloat {
        CGFloat(clamped(position)) * max(width, 0)
    }

    /// The place after a drag that started at `startX`, with the line at `start`, and is now at
    /// `x`: the line moves as far as the pointer, so it doesn't jump to it, and stops at the
    /// Viewer's edges. Without a width it stays.
    static func dragged(from start: Double, startX: CGFloat, to x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return clamped(start) }
        return clamped(clamped(start) + Double((x - startX) / width))
    }

    /// Whether a press at `point` takes the line at `lineX` in a viewport `height` high: within
    /// `reach` of it over the whole height, or on its knob. All in drawable pixels, `scale` per
    /// point.
    static func hits(_ point: CGPoint, lineX: CGFloat, height: CGFloat, scale: CGFloat) -> Bool {
        guard point.y >= 0, point.y <= height else { return false }
        if abs(point.x - lineX) <= reach * scale { return true }
        let knob = knobCenter(lineX: lineX, height: height)
        return hypot(point.x - knob.x, point.y - knob.y) <= knobRadius * scale
    }

    /// The knob's centre: on the line, at the viewport's mid-height.
    static func knobCenter(lineX: CGFloat, height: CGFloat) -> CGPoint {
        CGPoint(x: lineX, y: height / 2)
    }

    /// A label's size for text of `textSize`, on whole points.
    static func labelSize(textSize: CGSize) -> CGSize {
        CGSize(width: (textSize.width + 2 * labelPadding).rounded(.up), height: labelHeight)
    }

    /// The labels' top: under the lowest pill at the Viewer's top while one shows (`pillBottom`),
    /// as the simulation's pill stacks under another's (`ViewerIndicators`), else `labelTop`.
    static func labelsTop(below pillBottom: CGFloat?) -> CGFloat {
        pillBottom.map { ($0 + ViewerIndicators.spacing).rounded() } ?? labelTop
    }

    /// The side labels by the line at `lineX` in a viewport `width` wide: the left one ending
    /// `labelGap` left of it, the right one starting `labelGap` right of it, both at `top`, on
    /// whole points. A label that would come closer than `labelMargin` to the edge is left out
    /// (`nil`), so none is ever cut.
    static func labelRects(
        left: CGSize, right: CGSize, lineX: CGFloat, width: CGFloat, top: CGFloat
    )
        -> (left: CGRect?, right: CGRect?)
    {
        let leftRect = CGRect(
            x: (lineX - labelGap - left.width).rounded(), y: top, width: left.width, height: left.height)
        let rightRect = CGRect(x: (lineX + labelGap).rounded(), y: top, width: right.width, height: right.height)
        return (
            leftRect.minX >= labelMargin ? leftRect : nil,
            rightRect.maxX <= width - labelMargin ? rightRect : nil
        )
    }

    /// Whether a copy of the view `width` wide shows the line at `x` (both in its pixels), and with
    /// it the side labels: when the line falls inside it. A copy of the whole view always holds the
    /// line; a selection or a region beside it is all one side, and holds neither.
    static func isInCopy(x: CGFloat, width: CGFloat) -> Bool {
        x >= 0 && x <= width
    }
}
