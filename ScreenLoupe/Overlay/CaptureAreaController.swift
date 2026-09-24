import AppKit

/// Owns the Capture Area: its rect, the overlay window, dragging, arrow keys, hover and persistence.
@MainActor
final class CaptureAreaController {
    /// The captured rect, in AppKit global coordinates, snapped to its display's pixel grid.
    private(set) var captureRect: CGRect = .zero
    /// Called whenever `captureRect` changes.
    var onChange: (() -> Void)?
    /// Called when the mouse moves anywhere on screen while the frame is shown.
    var onMouseMoved: (() -> Void)?

    /// What to capture for the current rect, or `nil` when it is on no display.
    var captureGeometry: CaptureGeometry? {
        converter?.captureGeometry(for: GlobalRect(rect: captureRect))
    }

    private let window = CaptureOverlayWindow()
    private let view: CaptureOverlayView
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
        view = CaptureOverlayView(style: Self.style(settings.settings))
        window.contentView = view
        view.delegate = self
        view.isPinned = settings.settings.captureAreaPinned
        refreshDisplays()
        apply(initialRect(), persist: false)

        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            keyObservers.append(
                center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.updateReveal() }
                })
        }
        settings.observe { [weak self] old, new in self?.settingsChanged(from: old, to: new) }
    }

    // MARK: Settings › Capture Area

    private static func style(_ settings: Settings) -> FrameStyle {
        FrameStyle(
            color: settings.frameColor, lineWidth: settings.frameLineWidth, showsLabelAtRest: settings.showsSizeAtRest)
    }

    private func settingsChanged(from old: Settings, to new: Settings) {
        if old.frameColor != new.frameColor || old.frameLineWidth != new.frameLineWidth
            || old.showsSizeAtRest != new.showsSizeAtRest
        {
            view.style = Self.style(new)
        }
        if old.sizeUnits != new.sizeUnits {
            apply(captureRect, persist: false)
        }
        if old.captureAreaPinned != new.captureAreaPinned {
            view.isPinned = new.captureAreaPinned
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
        // During a reconfiguration the screen list can be briefly empty; keep the old layout rather
        // than judging the area off-screen and overwriting the saved placement.
        guard DisplayLayout.current() != nil else { return }
        refreshDisplays()
        let onScreen = converter?.owningDisplay(for: GlobalRect(rect: captureRect)) != nil
        apply(onScreen ? captureRect : defaultRect(), persist: true)
    }

    private func refreshDisplays() {
        converter = DisplayLayout.current().map(DisplayCoordinateConverter.init(layout:))
    }

    private func initialRect() -> CGRect {
        if var saved = settings.settings.captureArea, converter?.owningDisplay(for: GlobalRect(rect: saved)) != nil {
            let minimum = CaptureAreaEditing.minimumSize
            saved.size = CGSize(width: max(saved.width, minimum.width), height: max(saved.height, minimum.height))
            return saved
        }
        return defaultRect()
    }

    private func defaultRect() -> CGRect {
        let screen =
            (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
        let size = Self.defaultSize
        // Left of centre, so the Viewer fits beside it on first launch (docs/design.md §7, acceptance step 3).
        let centerX = screen.minX + screen.width * 0.3
        return CGRect(
            x: centerX - size.width / 2, y: screen.midY - size.height / 2, width: size.width, height: size.height)
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

        let units = settings.settings.sizeUnits
        let tabText = SizeText.tab(rect.size, scale: scale, units: units)
        let labelText = SizeText.label(rect.size, scale: scale, units: units)
        // L T R B from the top-left corner of the display the area is on.
        let local = display.flatMap { display in
            converter?.displayLocalRect(GlobalRect(rect: rect), on: display).rect
        }
        let positionLines = local.map { SizeText.edges($0, scale: scale, units: units) } ?? []
        let layout = OverlayLayout(
            captureRect: rect,
            screenFrame: screenFrame,
            tabWidth: OverlayStyle.tabWidth(for: tabText),
            labelWidth: OverlayStyle.labelWidth(for: labelText),
            positionSize: positionLines.isEmpty ? .zero : OverlayStyle.positionSize(for: positionLines)
        )
        self.layout = layout
        window.setFrame(layout.windowFrame, display: false)
        view.update(layout: layout, tabText: tabText, labelText: labelText, positionLines: positionLines)

        if persist {
            settings.update { $0.captureArea = rect }
        }
        onChange?()
    }

    private func applyEdited(_ rect: CGRect, snap: Snap, persist: Bool) {
        // Resizing snaps each edge on its own, so the edges that don't move stay exactly in place;
        // `apply` then snaps as a whole, which leaves an already snapped rect unchanged.
        apply(snapped(rect, snap), persist: persist)
    }

    // MARK: Hover

    private func startMonitoringMouse() {
        guard eventMonitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
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
        onMouseMoved?()
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
    private var isPinned: Bool { settings.settings.captureAreaPinned }

    func overlayView(_ view: CaptureOverlayView, hitTargetAt point: CGPoint) -> OverlayHitTarget? {
        layout?.hitTarget(at: point, metrics: view.style.metrics, pinned: isPinned)
    }

    func overlayView(_ view: CaptureOverlayView, mouseDownAt point: CGPoint) {
        let target = layout?.hitTarget(at: point, metrics: view.style.metrics, pinned: isPinned)
        if target == .pin {
            settings.update { $0.captureAreaPinned.toggle() }
            return
        }
        // A pinned frame stays put. Otherwise the window only receives presses on its drawn pixels,
        // and anything that isn't a handle moves it.
        guard !isPinned else { return }
        drag = Drag(target: target ?? .move, startMouse: point, startRect: captureRect)
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
        case .pin:
            break
        }
    }

    func overlayViewMouseUp(_ view: CaptureOverlayView) {
        guard drag != nil else { return }
        drag = nil
        settings.update { $0.captureArea = captureRect }
        mouseMovedAnywhere()
    }

    func overlayView(_ view: CaptureOverlayView, keyDown event: NSEvent) -> Bool {
        guard !isPinned else { return false }
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
