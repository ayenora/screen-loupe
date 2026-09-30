import CoreGraphics

/// Which ruler the Viewer's ruler button turns on and off.
enum RulerMode: String, Codable, CaseIterable, Sendable {
    /// A corner and two arms, placed by hand (`CornerRuler`).
    case corner
    /// The Select tool's selection's width and height (`SelectionRuler`).
    case selection
}

/// Which ruler is on: at most one, the one `mode` names.
struct RulerChoice: Equatable, Sendable {
    var mode: RulerMode
    var isOn: Bool

    /// The ruler button: the chosen mode's ruler on or off.
    func toggled() -> RulerChoice {
        RulerChoice(mode: mode, isOn: !isOn)
    }

    /// View › Corner Ruler and Selection Ruler: `mode`'s ruler on in place of the other, or off when
    /// it is on already.
    func toggled(_ mode: RulerMode) -> RulerChoice {
        RulerChoice(mode: mode, isOn: !(isOn && self.mode == mode))
    }

    /// A mode chosen in the ruler button's ▾: its ruler on in place of the other; one already on
    /// stays on.
    func turnedOn(_ mode: RulerMode) -> RulerChoice {
        RulerChoice(mode: mode, isOn: true)
    }
}

/// A ruler's length label: `32 px · 16 pt`, or `32 px` when a pixel is a point (a 1× display, an
/// image file). Both rulers show their lengths this way.
enum RulerLabel {
    static func text(pixels: CGFloat, sourceScale: CGFloat) -> String {
        let px = "\(Int(pixels)) px"
        guard sourceScale != 1 else { return px }
        return "\(px) · \(points(pixels / sourceScale)) pt"
    }

    /// `16`, or `16.5` when it isn't a whole number of points: one decimal.
    static func points(_ points: CGFloat) -> String {
        points == points.rounded() ? "\(Int(points))" : String(format: "%.1f", Double(points))
    }
}

/// The Selection Ruler: the Select tool's selection measured by two dimension lines, its width
/// above its top edge and its height left of its left edge, outside it so nothing covers its
/// pixels. A line with no room there, at the Viewer's edge, goes to the opposite side, and with no
/// room there either, inside the selection. Everything is in the overlay's points, y down: `rect`
/// is the selection where it shows, `bounds` the Viewer's image area.
enum SelectionRuler {
    /// Where a line is drawn, against the selection's edge it measures along.
    enum Side: Equatable, Sendable {
        /// Above the top edge, or left of the left edge.
        case outside
        /// Below the bottom edge, or right of the right edge.
        case opposite
        /// Inside, along the top or left edge.
        case inside
    }

    /// A dimension line from `start` to `end`, with end marks across it at both ends, and its label's pill.
    struct Line: Equatable, Sendable {
        var start: CGPoint
        var end: CGPoint
        var side: Side
        var label: CGRect
    }

    /// How far a line stands off the selection's edge.
    static let offset: CGFloat = 12
    /// How far the end marks reach each side of the line.
    static let markReach: CGFloat = 4
    /// The space between the height line and its label, which sits beside it.
    static let labelGap: CGFloat = 6

    /// Both lines. Over a selection shorter and narrower than the labels, the height's label, centred
    /// on its short line, would reach the width's at the corner they share; it then moves along its
    /// line, away from the width line, clear of its label; past it instead when that leaves the view.
    static func lines(
        of rect: CGRect, in bounds: CGRect, widthLabel: CGSize, heightLabel: CGSize
    ) -> (width: Line, height: Line) {
        let width = widthLine(of: rect, in: bounds, labelSize: widthLabel)
        var height = heightLine(of: rect, in: bounds, labelSize: heightLabel)
        if height.label.intersects(width.label) {
            let below = width.label.maxY + labelGap
            let above = width.label.minY - labelGap - heightLabel.height
            let (away, past) = width.side == .opposite ? (above, below) : (below, above)
            let fits = away >= bounds.minY && away + heightLabel.height <= bounds.maxY
            height.label.origin.y = fits ? away : past
        }
        return (width, height)
    }

    /// The width, with its label centred on the line: above the selection, else below, else inside
    /// along its top.
    static func widthLine(of rect: CGRect, in bounds: CGRect, labelSize: CGSize) -> Line {
        let half = labelSize.height / 2
        let side: Side
        let y: CGFloat
        if rect.minY - offset - half >= bounds.minY {
            (side, y) = (.outside, rect.minY - offset)
        } else if rect.maxY + offset + half <= bounds.maxY {
            (side, y) = (.opposite, rect.maxY + offset)
        } else {
            (side, y) = (.inside, max(rect.minY, bounds.minY) + offset)
        }
        let x = labelStart(rect.minX, rect.maxX, length: labelSize.width, within: bounds.minX, bounds.maxX)
        return Line(
            start: CGPoint(x: rect.minX, y: y), end: CGPoint(x: rect.maxX, y: y), side: side,
            label: CGRect(origin: CGPoint(x: x, y: (y - half).rounded()), size: labelSize))
    }

    /// The height, with its label beside the line away from the selection (towards it, inside):
    /// left of the selection, else right of it, else inside along its left edge.
    static func heightLine(of rect: CGRect, in bounds: CGRect, labelSize: CGSize) -> Line {
        let reach = offset + labelGap + labelSize.width
        let side: Side
        let x: CGFloat
        let labelX: CGFloat
        if rect.minX - reach >= bounds.minX {
            (side, x) = (.outside, rect.minX - offset)
            labelX = x - labelGap - labelSize.width
        } else if rect.maxX + reach <= bounds.maxX {
            (side, x) = (.opposite, rect.maxX + offset)
            labelX = x + labelGap
        } else {
            (side, x) = (.inside, max(rect.minX, bounds.minX) + offset)
            labelX = x + labelGap
        }
        let y = labelStart(rect.minY, rect.maxY, length: labelSize.height, within: bounds.minY, bounds.maxY)
        return Line(
            start: CGPoint(x: x, y: rect.minY), end: CGPoint(x: x, y: rect.maxY), side: side,
            label: CGRect(origin: CGPoint(x: labelX.rounded(), y: y), size: labelSize))
    }

    /// The space between the selection's size badge and the selection, or anything of the ruler it
    /// gives way to, and the badge's least distance from the Viewer's sides.
    static let badgeGap: CGFloat = 6
    static let badgeMargin: CGFloat = 4

    /// Where the selection's size badge (`PixelSelection.label`) of `size` goes, clear of the
    /// Selection Ruler's lines, marks and labels (`ruler`, `nil` while it is off), so nothing
    /// overlaps: under the selection's bottom-left corner, below whatever of the ruler is there;
    /// else over its top, above whatever is there; else, with no room either way (the selection fills
    /// the Viewer), inside it at the bottom of what shows, right of a height line along its left
    /// edge. With no place there clear of the ruler either (a badge wider than the room right of a
    /// height line), it stays at the bottom of what shows, over the line: never out of view. Its left
    /// edge follows the selection's, kept inside the Viewer, and a badge wider than the Viewer starts at
    /// its left side, so the size shows and the place is cut; on whole points.
    static func badgeRect(
        size: CGSize, for rect: CGRect, in bounds: CGRect, ruler: (width: Line, height: Line)?
    )
        -> CGRect
    {
        let lines = ruler.map { [$0.width, $0.height] } ?? []
        let obstacles = lines.flatMap { [area(of: $0), $0.label] }
        // Wider than the Viewer, it keeps to the left side: its end, the place, is what is cut, not the size.
        func placed(x: CGFloat, y: CGFloat) -> CGRect {
            CGRect(
                origin: CGPoint(
                    x: max(min(x, bounds.maxX - size.width - badgeMargin), bounds.minX + badgeMargin).rounded(),
                    y: y.rounded()),
                size: size)
        }
        func hit(_ badge: CGRect, among obstacles: [CGRect]) -> CGRect? {
            obstacles.first { $0.intersects(badge) }
        }

        var below = placed(x: rect.minX, y: rect.maxY + badgeGap)
        while let obstacle = hit(below, among: obstacles) {
            below = placed(x: below.minX, y: obstacle.maxY + badgeGap)
        }
        if below.maxY <= bounds.maxY { return below }

        var above = placed(x: rect.minX, y: rect.minY - badgeGap - size.height)
        while let obstacle = hit(above, among: obstacles) {
            above = placed(x: above.minX, y: obstacle.minY - badgeGap - size.height)
        }
        if above.minY >= bounds.minY { return above }

        // Past a height line along the left edge first, then up past the rest.
        var inside = placed(
            x: max(rect.minX, bounds.minX) + badgeGap, y: min(rect.maxY, bounds.maxY) - badgeGap - size.height)
        let height = ruler.map { [area(of: $0.height), $0.height.label] } ?? []
        while let obstacle = hit(inside, among: height) {
            let right = placed(x: obstacle.maxX + badgeGap, y: inside.minY)
            // Held at the Viewer's right side: it can go no further.
            guard right.minX > inside.minX else { break }
            inside = right
        }
        let bottom = inside.minY
        while let obstacle = hit(inside, among: obstacles) {
            inside = placed(x: inside.minX, y: obstacle.minY - badgeGap - size.height)
        }
        // No place clear of the ruler: back at the bottom of what shows, over a line rather than
        // out of view.
        if inside.minY < bounds.minY {
            inside.origin.y = max(bottom, bounds.minY)
        }
        return inside
    }

    /// What a line covers with its end marks.
    private static func area(of line: Line) -> CGRect {
        CGRect(
            x: min(line.start.x, line.end.x), y: min(line.start.y, line.end.y), width: abs(line.end.x - line.start.x),
            height: abs(line.end.y - line.start.y)
        ).insetBy(dx: -markReach, dy: -markReach)
    }

    /// Where a label of `length` along a line from `min` to `max` starts, on whole points: centred
    /// on the part of the line inside `lower...upper` and kept inside it, so it stays in view while
    /// the selection reaches beyond the Viewer; centred on the whole line when none of it is inside.
    private static func labelStart(
        _ min: CGFloat, _ max: CGFloat, length: CGFloat, within lower: CGFloat, _ upper: CGFloat
    ) -> CGFloat {
        let from = Swift.max(min, lower)
        let to = Swift.min(max, upper)
        guard from <= to else { return ((min + max) / 2 - length / 2).rounded() }
        return Swift.min(Swift.max(((from + to) / 2 - length / 2).rounded(), lower), upper - length)
    }
}
