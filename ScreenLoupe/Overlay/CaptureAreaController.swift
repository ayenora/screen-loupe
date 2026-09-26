import AppKit

/// Owns the Capture Area: its rect, the overlay window, dragging, arrow keys, hover, the magnet and
/// persistence.
@MainActor
final class CaptureAreaController {
    /// The captured rect, in AppKit global coordinates, snapped to its display's pixel grid.
    private(set) var captureRect: CGRect = .zero
    /// Called whenever `captureRect` changes.
    var onChange: (() -> Void)?
    /// Called when the mouse moves anywhere on screen while the frame is shown.
    var onMouseMoved: (() -> Void)?
    /// Called by the frame's raise button: bring the Viewer forward.
    var onRaiseViewer: (() -> Void)?
    /// Called by the frame's pick button: pick a window for the area.
    var onPickWindow: (() -> Void)?

    /// The part of the area the Viewer shows, in AppKit global coordinates; `nil` while it shows the
    /// whole area, or nothing of it live. Outlined while the Viewer's image moves and while the cursor
    /// is near the frame.
    var viewedPart: CGRect? {
        didSet {
            guard viewedPart != oldValue else { return }
            view.viewedPart = viewedPart
            updateViewedPartShown()
        }
    }

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
        /// Window and display edges to snap to while ⌘ is held, read on the first such move.
        var snapTargets: [CGRect]?
    }
    private var drag: Drag?
    private var isHovering = false
    private var isRevealed = false
    private var hideTimer: Timer?
    /// Runs while the outline of the viewed part holds after the Viewer's image moved.
    private var viewedPartTimer: Timer?
    private var eventMonitors: [Any] = []
    private var keyObservers: [NSObjectProtocol] = []
    private var picker: WindowPicker?

    /// The window the magnet holds and where the area sits on it; `nil` while it holds none.
    private struct Magnet {
        /// As last read.
        var window: ScreenWindow
        /// `WindowMagnet.placement`: taken on attaching and after a resize.
        var placement: CGRect
        /// Reads in a row that didn't hold the window.
        var badReads = 0
    }
    private var magnet: Magnet?
    /// Reads the held window's frame while the magnet holds one, and only then.
    private var magnetTimer: Timer?
    private var spaceObserver: NSObjectProtocol?
    /// The area followed its window since the placement was last saved.
    private var magnetMoved = false
    /// The notice beside the tab, while it shows.
    private var noticeText: String?
    private var noticeTimer: Timer?

    private static let defaultSize = CGSize(width: 320, height: 200)

    init(settings: SettingsStore) {
        self.settings = settings
        view = CaptureOverlayView(style: FrameStyle(settings.settings.frameStyleSettings))
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
        // Settings › Capture Area. Each first call repeats what init just set up, harmlessly.
        settings.observe(\.frameStyleSettings) { [weak self] in self?.view.style = FrameStyle($0) }
        settings.observe(\.sizeUnits) { [weak self] _ in
            guard let self else { return }
            apply(captureRect, persist: false)
        }
        // The magnet's window doesn't survive a relaunch: a Magnet mode comes up off.
        settings.update { if $0.captureAreaLock == .magnet { $0.captureAreaLocked = false } }
        settings.observe(\.captureAreaLock) { [weak self] in self?.view.lock = $0 }
        settings.observe(\.captureAreaLocked) { [weak self] in self?.view.isLocked = $0 }
        // The magnet turned off, or another lock chosen.
        settings.observe(\.activeCaptureAreaLock) { [weak self] in
            if $0 != .magnet { self?.stopMagnet() }
        }
    }

    // MARK: Visibility

    var isVisible: Bool { window.isVisible }

    func show() {
        window.orderFrontRegardless()
        startMonitoringMouse()
    }

    /// A hidden area doesn't follow a window: the magnet turns off quietly, as at launch.
    func hide() {
        window.orderOut(nil)
        stopMonitoringMouse()
        if magnet != nil { settings.update { $0.captureAreaLocked = false } }
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    // MARK: Displays

    /// Rebuilds the display layout and keeps the area on a connected display.
    func screenParametersChanged() {
        // A read between the change and this call used the old layout: let go rather than follow
        // with frames that may be off.
        if magnet != nil { letGoOfMagnetWindow() }
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

    // MARK: Picking a window

    /// Lets the user pick a window, then makes the area that window, shown, and calls `onPicked`.
    /// Locked or not: the pin guards against a stray drag, and picking is a deliberate command. An
    /// attached magnet moves to the picked window.
    func pickWindow(onPicked: @escaping () -> Void) {
        pick(hint: "Click to fit the Capture Area · Esc to cancel") { [weak self] picked in
            guard let self else { return }
            let minimum = CaptureAreaEditing.minimumSize
            var rect = picked.frame
            rect.size = CGSize(width: max(rect.width, minimum.width), height: max(rect.height, minimum.height))
            applyEdited(rect, snap: .edges, persist: true)
            if magnet != nil { attach(to: picked) }
            show()
            onPicked()
        }
    }

    /// Opens the window picker; `onPicked` runs only when a window is picked.
    private func pick(hint: String, onPicked: @escaping (ScreenWindow) -> Void) {
        guard picker == nil, let converter else { return }
        let picker = WindowPicker(
            windows: ScreenWindows.windows(converter: converter), tint: view.style.accent, hint: hint
        ) { [weak self] picked in
            self?.picker = nil
            if let picked { onPicked(picked) }
        }
        self.picker = picker
        picker.start()
    }

    // MARK: Magnet

    /// Magnet to Window: the picked window holds the area where it is. Cancelling leaves the lock as
    /// it was.
    private func pickMagnetWindow() {
        pick(hint: "Click to attach the Capture Area · Esc to cancel") { [weak self] in self?.attach(to: $0) }
    }

    /// A click on the magnet while it is off: the window under the area holds it, if there is one.
    private func attachToWindowUnderArea() {
        guard let converter,
            let window = WindowMagnet.window(under: captureRect, in: ScreenWindows.windows(converter: converter))
        else { return }
        attach(to: window)
    }

    /// Holds the area on `window` without moving it, and starts reading the window's frame: about
    /// 60 times a second, one window at a time (docs/design.md, Capture Area).
    private func attach(to window: ScreenWindow) {
        magnet = Magnet(window: window, placement: WindowMagnet.placement(of: captureRect, on: window.frame))
        settings.update {
            $0.captureAreaLock = .magnet
            $0.captureAreaLocked = true
        }
        guard magnetTimer == nil else { return }
        magnetTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.followMagnetWindow() }
        }
        // A window going full screen, or the user leaving for another Space.
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.letGoOfMagnetWindow() }
        }
    }

    /// Moves the area with its window, or lets go when the window is gone. Waits out a drag of a
    /// handle: the window's move since then applies after it.
    private func followMagnetWindow() {
        guard let held = magnet, drag == nil, let converter else { return }
        let now = ScreenWindows.window(held.window.id, converter: converter)
        guard let now, WindowMagnet.holds(now) else {
            magnet?.badReads += 1
            if WindowMagnet.letsGo(afterBadReads: held.badReads + 1) { letGoOfMagnetWindow() }
            return
        }
        magnet?.badReads = 0
        if now.frame != held.window.frame {
            magnet?.window = now
            apply(WindowMagnet.area(at: held.placement, on: now.frame), persist: false)
            magnetMoved = true
        } else if magnetMoved {
            // Saved once the window stops, not on every step of its move.
            magnetMoved = false
            settings.update { $0.captureArea = captureRect }
        }
    }

    /// The window is gone: the area stays where it is, the magnet turns off and a notice says why.
    private func letGoOfMagnetWindow() {
        stopMagnet()
        settings.update { $0.captureAreaLocked = false }
        showNotice("Window gone · magnet off")
    }

    /// After a resize, the area keeps its new size and place on the window.
    private func rememberMagnetPlacement() {
        guard let held = magnet else { return }
        magnet?.placement = WindowMagnet.placement(of: captureRect, on: held.window.frame)
    }

    private func stopMagnet() {
        magnetTimer?.invalidate()
        magnetTimer = nil
        spaceObserver.map(NSWorkspace.shared.notificationCenter.removeObserver)
        spaceObserver = nil
        magnet = nil
        if magnetMoved {
            magnetMoved = false
            settings.update { $0.captureArea = captureRect }
        }
    }

    // MARK: Notice

    /// Shows `text` beside the tab for a moment, then fades it.
    private func showNotice(_ text: String) {
        noticeText = text
        apply(captureRect, persist: false)
        view.setNotice(text)
        noticeTimer?.invalidate()
        noticeTimer = Timer.scheduledTimer(withTimeInterval: OverlayStyle.noticeDelay, repeats: false) {
            [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.noticeTimer = nil
                // The room it took goes with the next layout.
                self.noticeText = nil
                self.view.setNotice(nil)
            }
        }
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
            positionSize: positionLines.isEmpty ? .zero : OverlayStyle.positionSize(for: positionLines),
            noticeWidth: noticeText.map(OverlayStyle.labelWidth(for:)) ?? 0
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
        let wasNear = isNear
        isHovering = layout?.isInHoverZone(NSEvent.mouseLocation) ?? false
        // The outline holds a moment after the cursor leaves, as the handles do.
        if wasNear, !isNear { flashViewedPart() }
        updateReveal()
        onMouseMoved?()
    }

    /// The handles and tab show while the cursor is near the frame, while dragging, and while the
    /// frame is key (after a click, so arrow-key nudges are visible).
    private func updateReveal() {
        updateViewedPartShown()
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

    // MARK: The part the Viewer shows

    /// The cursor is near the frame, or dragging it. Unlike the handles, the outline doesn't stay
    /// while the frame is key: it would sit over the content until another window is clicked.
    private var isNear: Bool { isHovering || drag != nil }

    /// Shows the outline for as long as the handles stay after the cursor leaves: the Viewer's image
    /// panned or zoomed, or the cursor left the frame.
    func flashViewedPart() {
        viewedPartTimer?.invalidate()
        viewedPartTimer = Timer.scheduledTimer(withTimeInterval: OverlayStyle.hideDelay, repeats: false) {
            [weak self] _ in
            MainActor.assumeIsolated {
                self?.viewedPartTimer = nil
                self?.updateViewedPartShown()
            }
        }
        updateViewedPartShown()
    }

    private func updateViewedPartShown() {
        view.setViewedPartShown(viewedPart != nil && (isNear || viewedPartTimer != nil))
    }
}

// MARK: - Mouse and keys

extension CaptureAreaController: CaptureOverlayViewDelegate {
    private var lock: CaptureAreaLock? { settings.settings.activeCaptureAreaLock }

    func overlayView(_ view: CaptureOverlayView, hitTargetAt point: CGPoint) -> OverlayHitTarget? {
        layout?.hitTarget(at: point, metrics: view.style.metrics, lock: lock)
    }

    func overlayView(_ view: CaptureOverlayView, mouseDownAt point: CGPoint) {
        let target = layout?.hitTarget(at: point, metrics: view.style.metrics, lock: lock)
        if target == .pin {
            let current = settings.settings
            if current.captureAreaLock == .magnet, !current.captureAreaLocked {
                attachToWindowUnderArea()
            } else {
                settings.update { $0.captureAreaLocked.toggle() }
            }
            return
        }
        if target == .pinMenu {
            view.showLockMenu()
            return
        }
        if target == .raiseViewer {
            onRaiseViewer?()
            return
        }
        if target == .pickWindow {
            onPickWindow?()
            return
        }
        // A locked frame takes only the handles its lock allows, which the hit test already left out.
        // Otherwise the window only receives presses on its drawn pixels, and anything that isn't a
        // handle moves it.
        guard let target = target ?? (lock == nil ? .move : nil) else { return }
        drag = Drag(target: target, startMouse: point, startRect: captureRect)
        updateReveal()
    }

    func overlayView(_ view: CaptureOverlayView, mouseDraggedTo point: CGPoint) {
        guard let drag else { return }
        let delta = CGVector(dx: point.x - drag.startMouse.x, dy: point.y - drag.startMouse.y)
        // With ⌘ held, edges snap to windows and displays (docs/product.md, Capture Area).
        let targets = NSEvent.modifierFlags.contains(.command) ? snapTargets() : []
        switch drag.target {
        case .move:
            let moved = drag.startRect.offsetBy(dx: delta.dx, dy: delta.dy)
            applyEdited(EdgeSnapping.moved(moved, targets: targets), snap: .move, persist: false)
        case .resize(let handle):
            let resized = CaptureAreaEditing.resized(drag.startRect, handle: handle, by: delta)
            var rect = EdgeSnapping.resized(resized, handle: handle, targets: targets)
            // With Shift a corner keeps the area square, after ⌘-snapping: the longer side wins. Squared
            // after the pixel snap, so both sides come out the same whole number of pixels. Squared twice:
            // the square can end up owned by a display with another scale, whose grid the second pass uses.
            if NSEvent.modifierFlags.contains(.shift) {
                let square = CaptureAreaEditing.squared(snapped(rect, .edges), handle: handle)
                rect = CaptureAreaEditing.squared(snapped(square, .edges), handle: handle)
            }
            applyEdited(rect, snap: .edges, persist: false)
        case .pin, .pinMenu, .raiseViewer, .pickWindow:
            break
        }
    }

    /// Read once per drag: windows don't move while the frame is dragged.
    private func snapTargets() -> [CGRect] {
        if let targets = drag?.snapTargets { return targets }
        guard let converter else { return [] }
        let targets = ScreenWindows.frames(converter: converter) + converter.layout.displays.map(\.globalFrame)
        drag?.snapTargets = targets
        return targets
    }

    func overlayViewMouseUp(_ view: CaptureOverlayView) {
        guard drag != nil else { return }
        drag = nil
        rememberMagnetPlacement()
        settings.update { $0.captureArea = captureRect }
        mouseMovedAnywhere()
    }

    /// A lock chosen from the pin's ▾ is also turned on; the magnet first asks for its window.
    func overlayView(_ view: CaptureOverlayView, didChoose lock: CaptureAreaLock) {
        if lock == .magnet {
            pickMagnetWindow()
            return
        }
        settings.update {
            $0.captureAreaLock = lock
            $0.captureAreaLocked = true
        }
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
        if let lock, !lock.allowsNudge(resizing: resize) { return false }
        let next = CaptureAreaEditing.nudged(captureRect, key: key, step: step, resize: resize)
        applyEdited(next, snap: resize ? .edges : .move, persist: true)
        rememberMagnetPlacement()
        return true
    }
}
