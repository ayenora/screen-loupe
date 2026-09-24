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

    /// 0…1. An unpinned ruler stays put while the image pans or zooms under it, so it would jitter
    /// from pixel to pixel; it hides meanwhile and eases back in once the image settles.
    private(set) var visibility: CGFloat = 1
    private var settleTimer: Timer?
    private var fadeTask: Task<Void, Never>?
    private var unhoverTimer: Timer?
    /// How long the pin button stays after the pointer leaves.
    private static let unhoverDelay: TimeInterval = 0.6
    private static let settleDelay: TimeInterval = 0.12
    private static let fadeDuration: TimeInterval = 0.12

    private let zoomPan: ZoomPanController
    private let project: ProjectStore
    private var drag: (part: Part, last: CGPoint)?

    init(zoomPan: ZoomPanController, project: ProjectStore) {
        self.zoomPan = zoomPan
        self.project = project
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
        fadeTask?.cancel()
        visibility = 1
        changed()
    }

    func drawn(scale: CGFloat) -> Drawn? {
        guard let ruler else { return nil }
        let state = zoomPan.state
        let placed = ruler.placement(in: state, minimum: Self.minimumLength * scale)
        let corner = state.viewportPoint(forSourcePoint: placed.corner)
        let pinShift = Self.pinDistance * scale / 2.squareRoot()
        return Drawn(
            placement: placed, corner: corner,
            horizontalEnd: CGPoint(x: corner.x + placed.arms.width * state.zoom, y: corner.y),
            verticalEnd: CGPoint(x: corner.x, y: corner.y + placed.arms.height * state.zoom),
            pin: CGPoint(
                x: corner.x + (placed.arms.width < 0 ? pinShift : -pinShift),
                y: corner.y + (placed.arms.height < 0 ? pinShift : -pinShift)))
    }

    func part(at point: CGPoint, scale: CGFloat) -> Part? {
        // Hidden or fading in, the ruler still takes a press where it is, rather than letting it pan.
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

    /// The image panned or zoomed: an unpinned ruler hides until it settles, then eases back in.
    func viewportChanged() {
        guard let ruler, !ruler.isPinned else { return }
        fadeTask?.cancel()
        fadeTask = nil
        if visibility != 0 {
            visibility = 0
            changed()
        }
        settleTimer?.invalidate()
        settleTimer = Timer.scheduledTimer(withTimeInterval: Self.settleDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fadeIn() }
        }
    }

    /// Fully visible at once, for a press while it was hidden or fading in.
    private func showNow() {
        settleTimer?.invalidate()
        settleTimer = nil
        fadeTask?.cancel()
        fadeTask = nil
        guard visibility != 1 else { return }
        visibility = 1
        changed()
    }

    private func fadeIn() {
        settleTimer = nil
        fadeTask = Task { [weak self] in
            let start = ContinuousClock.now
            while !Task.isCancelled {
                let elapsed = ContinuousClock.now - start
                let t = min(1, CGFloat(elapsed / .milliseconds(Int(Self.fadeDuration * 1000))))
                guard let self else { return }
                // Ease out: most of the way at once, settling softly.
                visibility = 1 - (1 - t) * (1 - t)
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
        showNow()
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
