import AppKit

/// The corner ruler in the Viewer (docs/product.md, Ruler): its state, hit-testing and dragging.
/// The geometry is `CornerRuler`; points here are drawable pixels, y down, as in `ZoomPanState`.
@MainActor
final class RulerController {
    enum Part: Equatable {
        case line, corner, end(CornerRuler.Arm), pin
    }

    /// Where the ruler's parts are drawn, in drawable pixels.
    struct Drawn {
        var placement: CornerRuler.Placement
        var corner: CGPoint
        var horizontalEnd: CGPoint
        var verticalEnd: CGPoint
        /// The pin button, in the corner's outer (270°) angle.
        var pin: CGPoint
        /// On whole source pixels, so the lengths are exact; off them while the image moves.
        var isOnPixels: Bool
    }

    /// The shortest an arm looks, so the handles at its ends never touch.
    static let minimumLength: CGFloat = 32
    static let handleRadius: CGFloat = 5
    /// How close to a handle a press still takes it.
    static let grabRadius: CGFloat = 10
    static let pinRadius: CGFloat = 9
    static let pinDistance: CGFloat = 18
    /// How close to the line a press still takes it.
    static let lineReach: CGFloat = 5

    /// Kept in the project, so it comes back at launch.
    private(set) var ruler: CornerRuler? {
        didSet { if ruler != oldValue { project.update { [ruler] in $0.ruler = ruler } } }
    }
    /// The pointer is over the ruler or its pin button, or was a moment ago: the pin button and the
    /// move band show.
    private(set) var isHovered = false
    private var observers: [() -> Void] = []

    /// Calls `observer` after every change of the ruler or how it shows.
    func observe(_ observer: @escaping () -> Void) {
        observers.append(observer)
    }

    private func changed() {
        observers.forEach { $0() }
    }

    /// 0…1: how far an unpinned ruler is on its pixels. While the image pans or zooms under it, it
    /// stays still in the Viewer off the pixel grid (0) instead of jumping from pixel to pixel; once
    /// the image settles it eases onto the pixels (1). It never hides.
    private var snap: CGFloat = 1
    private var settleTimer: Timer?
    private var snapTask: Task<Void, Never>?
    /// The view and the drawable scale it was last drawn with, to fix the ruler where it showed
    /// when the image starts to move.
    private var lastState: ZoomPanState
    private var lastScale: CGFloat = 1
    private var unhoverTimer: Timer?
    /// How long the pin button stays after the pointer leaves.
    private static let unhoverDelay: TimeInterval = 0.6
    private static let settleDelay: TimeInterval = 0.12
    private static let snapDuration: TimeInterval = 0.12

    private let zoomPan: ZoomPanController
    private let project: ProjectStore
    private var drag: (part: Part, last: CGPoint)?

    init(zoomPan: ZoomPanController, project: ProjectStore) {
        self.zoomPan = zoomPan
        self.project = project
        lastState = zoomPan.state
        ruler = project.project.ruler
    }

    var isOn: Bool { ruler != nil }
    var isDragging: Bool { drag != nil }

    /// Turning the ruler off forgets it; turning it on starts a new, unpinned one.
    func toggle() {
        ruler = ruler == nil ? CornerRuler.starting(in: zoomPan.state.viewportSize) : nil
        isHovered = false
        drag = nil
        settleTimer?.invalidate()
        unhoverTimer?.invalidate()
        snapTask?.cancel()
        snap = 1
        changed()
    }

    /// The Capture Area's top-left corner moved by `shift` source pixels: a pinned ruler stays on its
    /// pixels (`CornerRuler.followAreaOrigin`).
    func areaOriginMoved(by shift: CGPoint) {
        guard shift != .zero, ruler?.isPinned == true else { return }
        ruler?.followAreaOrigin(shift: shift)
        changed()
    }

    func drawn(scale: CGFloat) -> Drawn? {
        lastState = zoomPan.state
        lastScale = scale
        return drawn(in: zoomPan.state, scale: scale)
    }

    /// Between the free placement and the one on pixels, as far as `snap` says.
    private func drawn(in state: ZoomPanState, scale: CGFloat) -> Drawn? {
        guard let ruler else { return nil }
        let minimum = Self.minimumLength * scale
        var placed = ruler.placement(in: state, minimum: minimum)
        var corner = state.viewportPoint(forSourcePoint: placed.corner)
        var arms = CGSize(width: placed.arms.width * state.zoom, height: placed.arms.height * state.zoom)
        if snap < 1, let free = ruler.freePlacement(in: state, minimum: minimum) {
            func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * snap }
            corner = CGPoint(x: mix(free.corner.x, corner.x), y: mix(free.corner.y, corner.y))
            arms = CGSize(width: mix(free.arms.width, arms.width), height: mix(free.arms.height, arms.height))
            // The lengths it would have on pixels, shown dimmed until it gets there.
            placed.arms = CGSize(
                width: Self.signed((arms.width / state.zoom).rounded()),
                height: Self.signed((arms.height / state.zoom).rounded()))
        }
        let pinShift = Self.pinDistance * scale / 2.squareRoot()
        return Drawn(
            placement: placed, corner: corner,
            horizontalEnd: CGPoint(x: corner.x + arms.width, y: corner.y),
            verticalEnd: CGPoint(x: corner.x, y: corner.y + arms.height),
            pin: CGPoint(
                x: corner.x + (arms.width < 0 ? pinShift : -pinShift),
                y: corner.y + (arms.height < 0 ? pinShift : -pinShift)),
            isOnPixels: snap >= 1 || ruler.isPinned)
    }

    /// A zero length keeps pointing right or down, as `CornerRuler` arms do.
    private static func signed(_ length: CGFloat) -> CGFloat {
        length == 0 ? 1 : length
    }

    func part(at point: CGPoint, scale: CGFloat) -> Part? {
        guard let ruler, let drawn = drawn(scale: scale) else { return nil }
        let grab = Self.grabRadius * scale
        if isHovered, distance(point, drawn.pin) <= Self.pinRadius * scale { return .pin }
        if distance(point, drawn.horizontalEnd) <= grab { return .end(.horizontal) }
        if distance(point, drawn.verticalEnd) <= grab { return .end(.vertical) }
        if !ruler.isPinned, distance(point, drawn.corner) <= grab { return .corner }
        let reach = Self.lineReach * scale
        if distance(point, toSegment: drawn.corner, drawn.horizontalEnd) <= reach
            || distance(point, toSegment: drawn.corner, drawn.verticalEnd) <= reach
        {
            return .line
        }
        return nil
    }

    /// Tracks the pointer (`nil`: it left the Viewer). The pin button shows while it is near and
    /// for a moment after, so it doesn't vanish on the way from the line to the button.
    func hover(at point: CGPoint?, scale: CGFloat) {
        var near = drag != nil
        if let point, let drawn = drawn(scale: scale) {
            near =
                near || part(at: point, scale: scale) != nil
                || distance(point, drawn.pin) <= Self.pinRadius * 1.5 * scale
        }
        if near {
            unhoverTimer?.invalidate()
            unhoverTimer = nil
            setHovered(true)
        } else if isHovered, unhoverTimer == nil {
            unhoverTimer = Timer.scheduledTimer(withTimeInterval: Self.unhoverDelay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.unhoverTimer = nil
                    self?.setHovered(false)
                }
            }
        }
    }

    private func setHovered(_ hovered: Bool) {
        guard hovered != isHovered else { return }
        isHovered = hovered
        changed()
    }

    /// The image panned or zoomed. An unpinned ruler stays where it showed, off the pixel grid, and
    /// eases onto the pixels once the image settles; also while it is being dragged.
    func viewportChanged() {
        guard let ruler, !ruler.isPinned else { return }
        if snap > 0, let shown = drawn(in: lastState, scale: lastScale) {
            // Fixed where it was drawn, on pixels or on the way there, so it doesn't jump now.
            self.ruler?.place(
                corner: shown.corner,
                arms: CGSize(
                    width: shown.horizontalEnd.x - shown.corner.x, height: shown.verticalEnd.y - shown.corner.y))
        }
        snapTask?.cancel()
        snapTask = nil
        snap = 0
        changed()
        settleTimer?.invalidate()
        settleTimer = Timer.scheduledTimer(withTimeInterval: Self.settleDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.easeOntoPixels() }
        }
    }

    private func easeOntoPixels() {
        settleTimer = nil
        snapTask = Task { [weak self] in
            let start = ContinuousClock.now
            while !Task.isCancelled {
                let elapsed = ContinuousClock.now - start
                let t = min(1, CGFloat(elapsed / .milliseconds(Int(Self.snapDuration * 1000))))
                guard let self else { return }
                // Ease out: most of the way at once, settling softly.
                snap = 1 - (1 - t) * (1 - t)
                changed()
                if t >= 1 { return }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    /// Takes a press on the ruler. Returns `false` when the press is not the ruler's; the line of a
    /// pinned ruler isn't, so it pans the image.
    func press(at point: CGPoint, scale: CGFloat) -> Bool {
        guard let part = part(at: point, scale: scale) else { return false }
        switch part {
        case .pin:
            ruler?.togglePin(in: zoomPan.state, minimum: Self.minimumLength * scale)
            changed()
        case .line where ruler?.isPinned == true:
            return false
        default:
            drag = (part, point)
        }
        return true
    }

    func drag(to point: CGPoint, scale: CGFloat) {
        guard let current = drag else { return }
        let minimum = Self.minimumLength * scale
        switch current.part {
        case .line:
            ruler?.move(by: CGPoint(x: point.x - current.last.x, y: point.y - current.last.y))
        case .corner:
            ruler?.setCorner(to: point, in: zoomPan.state, minimum: minimum)
        case .end(let arm):
            ruler?.setEnd(of: arm, to: point, in: zoomPan.state, minimum: minimum)
        case .pin:
            break
        }
        drag = (current.part, point)
        changed()
    }

    func endDrag() {
        drag = nil
    }

    static func cursor(for part: Part?, dragging: Bool) -> NSCursor? {
        switch part {
        case .line?: dragging ? .closedHand : .openHand
        case .corner?: .crosshair
        case .end(.horizontal)?: .resizeLeftRight
        case .end(.vertical)?: .resizeUpDown
        case .pin?: .pointingHand
        case nil: nil
        }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    /// Both segments are axis-aligned.
    private func distance(_ p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let x = min(max(p.x, min(a.x, b.x)), max(a.x, b.x))
        let y = min(max(p.y, min(a.y, b.y)), max(a.y, b.y))
        return distance(p, CGPoint(x: x, y: y))
    }
}
