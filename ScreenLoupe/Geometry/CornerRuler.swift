import CoreGraphics

/// The corner ruler in the Viewer (docs/product.md, Ruler): a corner and two arms, one horizontal
/// and one vertical, each pointing either way. It measures in whole source pixels: the corner and
/// the arm ends always sit on pixel boundaries.
///
/// Lengths are drawable pixels (the Viewer's device pixels, as in `ZoomPanState`) or source pixels,
/// as each name says. `minimum` is the shortest an arm may look, in drawable pixels, so the handles
/// at its ends never touch.
struct CornerRuler: Equatable, Sendable, Codable {
    enum Anchor: Equatable, Sendable, Codable {
        /// Fixed in the Viewer: the image pans and zooms under it. Drawable pixels, unsnapped.
        case viewer(corner: CGPoint, arms: CGSize)
        /// Pinned to the image: panning and zooming move it along. Source pixels; `arms` are the
        /// lengths the user set, which the ruler keeps even while zooming out lengthens it.
        case image(corner: CGPoint, arms: CGSize)
    }

    enum Arm: Sendable {
        case horizontal, vertical
    }

    var anchor: Anchor

    var isPinned: Bool {
        if case .image = anchor { return true }
        return false
    }

    /// Where the ruler is drawn: the corner in source pixels, the arms signed source pixels (right
    /// and down are positive). All whole numbers.
    struct Placement: Equatable, Sendable {
        var corner: CGPoint
        var arms: CGSize
    }

    /// A new ruler, fixed in the Viewer, a third of the way into `viewport` (drawable pixels).
    static func starting(in viewport: CGSize) -> CornerRuler {
        CornerRuler(
            anchor: .viewer(
                corner: CGPoint(x: viewport.width / 3, y: viewport.height / 3),
                arms: CGSize(width: viewport.width / 3, height: viewport.height / 3)))
    }

    func placement(in state: ZoomPanState, minimum: CGFloat) -> Placement {
        let shortest = Self.shortestArm(zoom: state.zoom, minimum: minimum)
        switch anchor {
        case .viewer(let corner, let arms):
            // Kept inside the viewport: after a move to a display with another scale, or a smaller
            // window, the saved spot may lie beyond it.
            let inside = CGPoint(
                x: min(max(corner.x, 0), state.viewportSize.width), y: min(max(corner.y, 0), state.viewportSize.height))
            let source = state.sourcePoint(forViewportPoint: inside)
            return Placement(
                corner: CGPoint(x: source.x.rounded(), y: source.y.rounded()),
                arms: CGSize(
                    width: Self.arm((arms.width / state.zoom).rounded(), shortest: shortest),
                    height: Self.arm((arms.height / state.zoom).rounded(), shortest: shortest)))
        case .image(let corner, let arms):
            return Placement(
                corner: corner,
                arms: CGSize(
                    width: Self.arm(arms.width, shortest: shortest), height: Self.arm(arms.height, shortest: shortest)))
        }
    }

    // MARK: Editing

    /// Pins the ruler where it is drawn now, or unpins it where it is drawn now.
    mutating func togglePin(in state: ZoomPanState, minimum: CGFloat) {
        let placed = placement(in: state, minimum: minimum)
        if isPinned {
            anchor = .viewer(
                corner: state.viewportPoint(forSourcePoint: placed.corner),
                arms: CGSize(width: placed.arms.width * state.zoom, height: placed.arms.height * state.zoom))
        } else {
            anchor = .image(corner: placed.corner, arms: placed.arms)
        }
    }

    /// Dragging the line moves the whole ruler; a pinned ruler stays.
    mutating func move(by delta: CGPoint) {
        guard case .viewer(let corner, let arms) = anchor else { return }
        anchor = .viewer(corner: CGPoint(x: corner.x + delta.x, y: corner.y + delta.y), arms: arms)
    }

    /// Dragging an arm's end to `point` (drawable pixels) sets that arm's length and side. It flips
    /// to the other side only once the end is a full shortest arm past the corner.
    mutating func setEnd(of arm: Arm, to point: CGPoint, in state: ZoomPanState, minimum: CGFloat) {
        let placed = placement(in: state, minimum: minimum)
        let shortest = Self.shortestArm(zoom: state.zoom, minimum: minimum)
        let source = state.sourcePoint(forViewportPoint: point)
        let raw = arm == .horizontal ? (source.x - placed.corner.x).rounded() : (source.y - placed.corner.y).rounded()
        let previous = arm == .horizontal ? placed.arms.width : placed.arms.height
        let length = abs(raw) >= shortest ? raw : (previous < 0 ? -shortest : shortest)
        switch anchor {
        case .viewer(let corner, _):
            var arms = placed.arms
            if arm == .horizontal { arms.width = length } else { arms.height = length }
            anchor = .viewer(
                corner: corner, arms: CGSize(width: arms.width * state.zoom, height: arms.height * state.zoom))
        case .image(let corner, var arms):
            // Only the dragged arm changes; the other keeps the length it was set to.
            if arm == .horizontal { arms.width = length } else { arms.height = length }
            anchor = .image(corner: corner, arms: arms)
        }
    }

    /// Dragging the corner moves it while both arm ends stay put; a pinned ruler's corner stays.
    mutating func setCorner(to point: CGPoint, in state: ZoomPanState, minimum: CGFloat) {
        guard case .viewer = anchor else { return }
        let placed = placement(in: state, minimum: minimum)
        let ends = CGPoint(x: placed.corner.x + placed.arms.width, y: placed.corner.y + placed.arms.height)
        let shortest = Self.shortestArm(zoom: state.zoom, minimum: minimum)
        let source = state.sourcePoint(forViewportPoint: point)
        // The corner may come no closer to either end than the shortest arm.
        func corner(_ value: CGFloat, end: CGFloat, arm: CGFloat) -> CGFloat {
            let rounded = value.rounded()
            return arm > 0 ? min(rounded, end - shortest) : max(rounded, end + shortest)
        }
        let newCorner = CGPoint(
            x: corner(source.x, end: ends.x, arm: placed.arms.width),
            y: corner(source.y, end: ends.y, arm: placed.arms.height))
        anchor = .viewer(
            corner: state.viewportPoint(forSourcePoint: newCorner),
            arms: CGSize(
                width: (ends.x - newCorner.x) * state.zoom, height: (ends.y - newCorner.y) * state.zoom))
    }

    // MARK: Helpers

    /// The shortest arm in whole source pixels that still looks `minimum` drawable pixels long.
    static func shortestArm(zoom: CGFloat, minimum: CGFloat) -> CGFloat {
        max(1, (minimum / zoom).rounded(.up))
    }

    /// `length` lengthened to `shortest` if needed, keeping its side (a zero arm points right/down).
    private static func arm(_ length: CGFloat, shortest: CGFloat) -> CGFloat {
        let sign: CGFloat = length < 0 ? -1 : 1
        return sign * max(abs(length), shortest)
    }
}
