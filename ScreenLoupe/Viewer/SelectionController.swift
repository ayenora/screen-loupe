import AppKit

/// Copying a part of the Viewer (docs/product.md, Screenshots): the Select tool's selection, snapped
/// to source pixels, and the free region of an Option-drag. The math is `PixelSelection` and
/// `ViewRegion`; points here are drawable pixels, y down, as in `ZoomPanState`.
@MainActor
final class SelectionController {
    enum Part: Equatable {
        case handle(SelectionHandle)
        case inside
    }

    /// The Select tool: while it is on, a drag selects instead of panning.
    private(set) var isToolOn = false
    /// The selection in source pixels from the Capture Area's top-left, as set; see `selection`.
    private var stored: CGRect?
    /// The Option-drag in progress, in viewport pixels.
    private(set) var region: CGRect?

    /// The side of a handle, and how close to its centre a press still takes it, in points.
    static let handleSize: CGFloat = 7
    static let grabRadius: CGFloat = 6
    /// A press that moves less than this, in points, is a click.
    static let clickThreshold: CGFloat = 3

    private enum Drag {
        /// A new selection from `start`; a click that never drags clears the selection instead.
        case select(start: CGPoint, hasMoved: Bool)
        case resize(SelectionHandle)
        case move(start: CGPoint, rect: CGRect)
        case region(start: CGPoint)
    }

    private var drag: Drag?
    private let zoomPan: ZoomPanController
    private var observers: [() -> Void] = []

    init(zoomPan: ZoomPanController) {
        self.zoomPan = zoomPan
    }

    /// Calls `observer` after every change of the tool, the selection or the region.
    func observe(_ observer: @escaping () -> Void) {
        observers.append(observer)
    }

    private func changed() {
        observers.forEach { $0() }
    }

    /// The selection inside the current Capture Area, or `nil` when there is none (or the area
    /// shrank away from it).
    var selection: CGRect? {
        stored.flatMap { PixelSelection.clamped($0, to: zoomPan.state.contentSize) }
    }

    var isDragging: Bool { drag != nil }

    /// Turning the tool off drops the selection with it.
    func toggleTool() {
        isToolOn.toggle()
        if !isToolOn { stored = nil }
        drag = nil
        changed()
    }

    /// Edit › Select All (⌘A): the whole Capture Area, turning the tool on if it is off.
    func selectAll() {
        let size = zoomPan.state.contentSize
        guard size.width > 0, size.height > 0 else { return }
        isToolOn = true
        stored = CGRect(origin: .zero, size: size)
        drag = nil
        changed()
    }

    /// The Capture Area's top-left corner moved by `shift` source pixels (its left or top edge was
    /// dragged): the selection stays on its pixels, as the image does.
    func areaOriginMoved(by shift: CGPoint) {
        guard shift != .zero, let rect = stored else { return }
        stored = PixelSelection.followingAreaOrigin(rect, shift: shift)
        changed()
    }

    /// Clears the selection; returns whether there was one.
    @discardableResult
    func clearSelection() -> Bool {
        guard stored != nil else { return false }
        stored = nil
        changed()
        return true
    }

    /// The selection as set, to keep while another picture shows and bring back after: each recent
    /// capture and the live view have their own (docs/product.md, Recent Captures). With the tool
    /// off nothing comes back, as turning it off drops the selection.
    var keptSelection: CGRect? {
        get { stored }
        set {
            stored = isToolOn ? newValue : nil
            drag = nil
            changed()
        }
    }

    // MARK: The Select tool

    func part(at point: CGPoint, scale: CGFloat) -> Part? {
        guard isToolOn, let rect = selection else { return nil }
        let state = zoomPan.state
        let grab = Self.grabRadius * scale
        for handle in SelectionHandle.allCases {
            let center = PixelSelection.handlePoint(handle, of: rect, in: state)
            if abs(point.x - center.x) <= grab, abs(point.y - center.y) <= grab { return .handle(handle) }
        }
        return state.imageRect(origin: rect.origin, size: rect.size).contains(point) ? .inside : nil
    }

    /// Takes a press while the tool is on: a handle resizes, the inside moves, anywhere else starts
    /// a new selection. Returns `false` with the tool off.
    func press(at point: CGPoint, scale: CGFloat) -> Bool {
        guard isToolOn else { return false }
        switch part(at: point, scale: scale) {
        case .handle(let handle)?: drag = .resize(handle)
        case .inside?: drag = selection.map { .move(start: point, rect: $0) }
        case nil: drag = .select(start: point, hasMoved: false)
        }
        return true
    }

    /// Starts an Option-drag at `point`, with the tool on or off.
    func beginRegion(at point: CGPoint) {
        drag = .region(start: point)
    }

    func drag(to point: CGPoint, scale: CGFloat) {
        let state = zoomPan.state
        switch drag {
        case .select(let start, let hasMoved)?:
            guard hasMoved || hypot(point.x - start.x, point.y - start.y) >= Self.clickThreshold * scale else { return }
            drag = .select(start: start, hasMoved: true)
            stored = PixelSelection.rect(from: start, to: point, in: state)
        case .resize(let handle)?:
            guard let rect = selection else { return }
            stored = PixelSelection.resized(
                rect, handle: handle, to: state.sourcePoint(forViewportPoint: point), contentSize: state.contentSize)
        case .move(let start, let rect)?:
            let delta = CGPoint(x: (point.x - start.x) / state.zoom, y: (point.y - start.y) / state.zoom)
            stored = PixelSelection.moved(rect, by: delta, contentSize: state.contentSize)
        case .region(let start)?:
            region = ViewRegion.rect(from: start, to: point, viewport: state.viewportSize)
        case nil:
            return
        }
        changed()
    }

    /// Ends the drag. Returns the region of an Option-drag, to copy.
    func endDrag() -> CGRect? {
        defer {
            drag = nil
            region = nil
            changed()
        }
        switch drag {
        case .select(_, let hasMoved)? where !hasMoved: stored = nil
        case .region?: return region
        default: break
        }
        return nil
    }

    static func cursor(for part: Part?) -> NSCursor {
        switch part {
        case .handle(let handle)?:
            // The same resize cursors as the Capture Area's, whose handles are y up.
            let overlay: OverlayHandle
            switch handle {
            case .topLeft: overlay = .topLeft
            case .top: overlay = .top
            case .topRight: overlay = .topRight
            case .left: overlay = .left
            case .right: overlay = .right
            case .bottomLeft: overlay = .bottomLeft
            case .bottom: overlay = .bottom
            case .bottomRight: overlay = .bottomRight
            }
            return OverlayStyle.cursor(for: .resize(overlay))
        case .inside?: return .openHand
        case nil: return .crosshair
        }
    }
}
