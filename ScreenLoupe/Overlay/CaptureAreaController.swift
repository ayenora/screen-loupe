import AppKit

/// Owns the Capture Area: its rect, the overlay window, dragging, arrow keys, hover and persistence.
@MainActor
final class CaptureAreaController {
    /// The captured rect, in AppKit global coordinates, snapped to its display's pixel grid.
    private(set) var captureRect: CGRect = .zero
    /// Called whenever `captureRect` changes.
    var onChange: ((CGRect) -> Void)?

    private let window = CaptureOverlayWindow()
    private let view = CaptureOverlayView()
    private let settings: SettingsStore
    private var converter: DisplayCoordinateConverter?
    private var layout: OverlayLayout?

    private struct Drag {
        var target: OverlayHitTarget
        var startMouse: CGPoint
        var startRect: CGRect
    }
    private var drag: Drag?
    private var isHovering = false
    private var isRevealed = false
    private var hideTimer: Timer?
    private var eventMonitors: [Any] = []
    private var keyObservers: [NSObjectProtocol] = []

    private static let defaultSize = CGSize(width: 320, height: 200)

    init(settings: SettingsStore) {
        self.settings = settings
        window.contentView = view
        view.delegate = self
        refreshDisplays()
        apply(initialRect(), persist: false)

        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            keyObservers.append(
                center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.updateReveal() }
                })
        }
    }

    // MARK: Visibility

    var isVisible: Bool { window.isVisible }

    func show() {
        window.orderFrontRegardless()
        startMonitoringMouse()
    }

    func hide() {
        window.orderOut(nil)
        stopMonitoringMouse()
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    // MARK: Displays

    /// Rebuilds the display layout and keeps the area on a connected display.
    func screenParametersChanged() {
        refreshDisplays()
        let onScreen = converter?.owningDisplay(for: GlobalRect(rect: captureRect)) != nil
        apply(onScreen ? captureRect : defaultRect(), persist: true)
    }

    private func refreshDisplays() {
        converter = DisplayLayout.current().map(DisplayCoordinateConverter.init(layout:))
    }

    private func initialRect() -> CGRect {
        if let saved = settings.settings.captureArea, converter?.owningDisplay(for: GlobalRect(rect: saved)) != nil {
            return saved
        }
        return defaultRect()
    }

    private func defaultRect() -> CGRect {
        let screen =
            (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
        let size = Self.defaultSize
        return CGRect(
            x: screen.midX - size.width / 2, y: screen.midY - size.height / 2, width: size.width, height: size.height)
    }

    // MARK: Applying a rect

    private enum Snap { case move, edges }

    private func snapped(_ rect: CGRect, _ snap: Snap) -> CGRect {
        guard let converter else { return rect }
        switch snap {
        case .move: return converter.snapped(GlobalRect(rect: rect)).rect
        case .edges: return converter.snappedEdges(GlobalRect(rect: rect)).rect
        }
    }

    private func apply(_ rect: CGRect, persist: Bool) {
        let rect = snapped(rect, .move)
        captureRect = rect
        let display = converter?.owningDisplay(for: GlobalRect(rect: rect))
        let screenFrame = display?.globalFrame ?? NSScreen.main?.frame ?? rect
        let scale = display?.scale ?? 1

        let tabText = SizeText.pointsAndPixels(rect.size, scale: scale)
        let labelText = SizeText.points(rect.size)
        let layout = OverlayLayout(
            captureRect: rect,
            screenFrame: screenFrame,
            tabWidth: OverlayStyle.tabWidth(for: tabText),
            labelWidth: OverlayStyle.labelWidth(for: labelText)
        )
        self.layout = layout
        window.setFrame(layout.windowFrame, display: false)
        view.update(layout: layout, tabText: tabText, labelText: labelText)

        if persist {
            settings.update { $0.captureArea = rect }
        }
        onChange?(rect)
    }

    private func applyEdited(_ rect: CGRect, snap: Snap, persist: Bool) {
        // Resizing snaps each edge on its own, so the edges that don't move stay exactly in place;
        // `apply` then snaps as a whole, which leaves an already snapped rect unchanged.
        apply(snapped(rect, snap), persist: persist)
    }

    // MARK: Hover

    private func startMonitoringMouse() {
        guard eventMonitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let monitor = NSEvent.addGlobalMonitorForEvents(
            matching: mask,
            handler: { [weak self] _ in
                MainActor.assumeIsolated { self?.mouseMovedAnywhere() }
            })
        {
            eventMonitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: mask,
            handler: { [weak self] event in
                MainActor.assumeIsolated { self?.mouseMovedAnywhere() }
                return event
            })
        {
            eventMonitors.append(monitor)
        }
    }

    private func stopMonitoringMouse() {
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors.removeAll()
    }

    private func mouseMovedAnywhere() {
        isHovering = layout?.isInHoverZone(NSEvent.mouseLocation) ?? false
        updateReveal()
    }

    /// The handles and tab show while the cursor is near the frame, while dragging, and while the
    /// frame is key (after a click, so arrow-key nudges are visible).
    private func updateReveal() {
        let wanted = isHovering || drag != nil || window.isKeyWindow
        if wanted {
            hideTimer?.invalidate()
            hideTimer = nil
            setRevealed(true)
        } else if isRevealed, hideTimer == nil {
            hideTimer = Timer.scheduledTimer(withTimeInterval: OverlayStyle.hideDelay, repeats: false) {
                [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.hideTimer = nil
                    if !(self.isHovering || self.drag != nil || self.window.isKeyWindow) {
                        self.setRevealed(false)
                    }
                }
            }
        }
    }

    private func setRevealed(_ revealed: Bool) {
        guard revealed != isRevealed else { return }
        isRevealed = revealed
        view.setRevealed(revealed)
    }
}

// MARK: - Mouse and keys

extension CaptureAreaController: CaptureOverlayViewDelegate {
    func overlayView(_ view: CaptureOverlayView, hitTargetAt point: CGPoint) -> OverlayHitTarget? {
        layout?.hitTarget(at: point)
    }

    func overlayView(_ view: CaptureOverlayView, mouseDownAt point: CGPoint) {
        // The window only receives presses on its drawn pixels; anything that isn't a handle moves it.
        let target = layout?.hitTarget(at: point) ?? .move
        drag = Drag(target: target, startMouse: point, startRect: captureRect)
        updateReveal()
    }

    func overlayView(_ view: CaptureOverlayView, mouseDraggedTo point: CGPoint) {
        guard let drag else { return }
        let delta = CGVector(dx: point.x - drag.startMouse.x, dy: point.y - drag.startMouse.y)
        switch drag.target {
        case .move:
            applyEdited(drag.startRect.offsetBy(dx: delta.dx, dy: delta.dy), snap: .move, persist: false)
        case .resize(let handle):
            applyEdited(
                CaptureAreaEditing.resized(drag.startRect, handle: handle, by: delta), snap: .edges, persist: false)
        }
    }

    func overlayViewMouseUp(_ view: CaptureOverlayView) {
        guard drag != nil else { return }
        drag = nil
        settings.update { $0.captureArea = captureRect }
        mouseMovedAnywhere()
    }

    func overlayView(_ view: CaptureOverlayView, keyDown event: NSEvent) -> Bool {
        let key: CaptureAreaEditing.ArrowKey
        switch event.specialKey {
        case .leftArrow?: key = .left
        case .rightArrow?: key = .right
        case .upArrow?: key = .up
        case .downArrow?: key = .down
        default: return false
        }
        // One step is one pixel of the display the area is on (docs/design.md §3).
        let scale = converter?.owningDisplay(for: GlobalRect(rect: captureRect))?.scale ?? 1
        let flags = event.modifierFlags
        let step = (flags.contains(.shift) ? 10 : 1) / scale
        let resize = flags.contains(.option)
        let next = CaptureAreaEditing.nudged(captureRect, key: key, step: step, resize: resize)
        applyEdited(next, snap: resize ? .edges : .move, persist: true)
        return true
    }
}
