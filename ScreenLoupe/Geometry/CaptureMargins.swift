import CoreGraphics

/// The Capture Area's margins while it is fitted to its magnet's window: four distances in points from the frame's
/// edges inward. The frame stays on the window's
/// bounds; what is captured is the inner rect. Global coordinates, y up: the top margin is taken off
/// `maxY`.
struct CaptureMargins: Codable, Equatable, Sendable {
    var left: CGFloat = 0
    var top: CGFloat = 0
    var right: CGFloat = 0
    var bottom: CGFloat = 0

    enum Edge: CaseIterable, Sendable {
        case left, top, right, bottom

        /// The edge across the inner rect from this one.
        var opposite: Edge {
            switch self {
            case .left: .right
            case .top: .bottom
            case .right: .left
            case .bottom: .top
            }
        }

        var isHorizontal: Bool { self == .left || self == .right }
    }

    subscript(edge: Edge) -> CGFloat {
        get {
            switch edge {
            case .left: left
            case .top: top
            case .right: right
            case .bottom: bottom
            }
        }
        set {
            switch edge {
            case .left: left = newValue
            case .top: top = newValue
            case .right: right = newValue
            case .bottom: bottom = newValue
            }
        }
    }

    /// The margins that apply to a frame of `size`: these, giving way while the frame is too small
    /// for them to leave the inner rect `minimumSize` — the right and bottom margins first, then the
    /// left and top. The stored margins stay as they are, so they come back as the frame grows.
    func applied(to size: CGSize, minimumSize: CGSize = CaptureAreaEditing.minimumSize) -> CaptureMargins {
        let horizontal = Self.giveWay(first: right, then: left, room: size.width - minimumSize.width)
        let vertical = Self.giveWay(first: bottom, then: top, room: size.height - minimumSize.height)
        return CaptureMargins(
            left: horizontal.then, top: vertical.then, right: horizontal.first, bottom: vertical.first)
    }

    /// `frame` less the margins that apply to it.
    func inner(of frame: CGRect, minimumSize: CGSize = CaptureAreaEditing.minimumSize) -> CGRect {
        let m = applied(to: frame.size, minimumSize: minimumSize)
        return CGRect(
            x: frame.minX + m.left, y: frame.minY + m.bottom, width: frame.width - m.left - m.right,
            height: frame.height - m.top - m.bottom)
    }

    /// These margins with `edge` set to `value` points: whole points, at least 0, and at most what
    /// leaves the inner rect of a frame of `frameSize` `minimumSize` beside the opposite margin as it
    /// applies. The other margins stay as stored.
    func setting(
        _ edge: Edge, to value: CGFloat, frameSize: CGSize, minimumSize: CGSize = CaptureAreaEditing.minimumSize
    ) -> CaptureMargins {
        let opposite = applied(to: frameSize, minimumSize: minimumSize)[edge.opposite]
        let side = edge.isHorizontal ? frameSize.width - minimumSize.width : frameSize.height - minimumSize.height
        let room = max((side - opposite).rounded(.down), 0)
        var next = self
        next[edge] = min(max(value.rounded(), 0), room)
        return next
    }

    // MARK: Units

    /// Units the margins panel shows per point, as the position box does: the display's `scale`
    /// when only pixels are chosen, else 1.
    static func shownPerPoint(units: SizeUnits, scale: CGFloat) -> CGFloat {
        units == .pixels ? scale : 1
    }

    /// `points` in the panel's units, `factor` per point (`shownPerPoint`).
    static func shown(_ points: CGFloat, factor: CGFloat) -> CGFloat {
        points * factor
    }

    /// A value typed in the panel's units, `factor` per point, in whole points: 25 px on a 2×
    /// display is 13 pt, which then shows as 26 px.
    static func points(fromShown value: CGFloat, factor: CGFloat) -> CGFloat {
        (value / factor).rounded()
    }

    /// Two margins across from each other, cut to `room` together: `first` gives way before `then`.
    private static func giveWay(
        first: CGFloat, then: CGFloat, room: CGFloat
    ) -> (first: CGFloat, then: CGFloat) {
        var first = max(first, 0)
        var then = max(then, 0)
        let excess = first + then - max(room, 0)
        guard excess > 0 else { return (first, then) }
        let fromFirst = min(first, excess)
        first -= fromFirst
        then -= excess - fromFirst
        return (first, then)
    }
}

/// A caption that scrubs its value, as in Unity (the References panel's X, Y and Scale, the Capture
/// Area's margins): dragged left or right, it moves by `step` per point of travel, ×10 with Shift,
/// ×0.1 with Option.
enum Scrub {
    /// The value `travel` points of drag from where the drag began, at `start`: the drag sets start +
    /// travel, so rounding in whatever takes the value never eats small steps.
    static func value(from start: Double, travel: Double, step: Double, shift: Bool, option: Bool) -> Double {
        let factor = shift ? 10 : option ? 0.1 : 1
        return start + travel * step * factor
    }
}
