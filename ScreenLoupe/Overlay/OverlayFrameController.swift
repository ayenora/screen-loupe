import AppKit

/// Which frame an `OverlayFrameController` runs. Both share the overlay window, drawing, dragging,
/// ⌘-snapping, pixel snapping, the arrow keys, Fit to Window and the notice; only the Capture Area
/// has the pin's locks, the magnet, the raise button and the outline of the part the Viewer shows,
/// with its viewport handle.
enum OverlayFrameKind {
    /// The Capture Area the Viewer shows.
    case captureArea
    /// The Screenshot studio's frame (docs/product.md, Screenshot studio): orange, no locks.
    case studio

    /// Where its rect is kept between launches.
    var savedRect: WritableKeyPath<Settings, CGRect?> {
        switch self {
        case .captureArea: \.captureArea
        case .studio: \.studioFrame
        }
    }

    /// The settings it is drawn with.
    var style: KeyPath<Settings, FrameStyleSettings> {
        switch self {
        case .captureArea: \.frameStyleSettings
        case .studio: \.studioFrameStyleSettings
        }
    }

    /// The pin with its locks and the magnet, the viewport and raise buttons.
    var hasLocks: Bool { self == .captureArea }

    /// Placed when first shown, on the displays then connected, and kept only from then on. The
    /// Capture Area is placed at launch, for the Viewer to open beside it.
    var placedWhenFirstShown: Bool { self == .studio }

    var name: String {
        switch self {
        case .captureArea: "Capture Area"
        case .studio: "Studio Frame"
        }
    }
}

/// Owns a frame above the screen — the Capture Area, or the Screenshot studio's frame (`kind`): its
/// rect, the overlay window, dragging, arrow keys, hover, the magnet and persistence.
@MainActor
final class OverlayFrameController {
    /// The captured rect, in AppKit global coordinates, snapped to its display's pixel grid.
    private(set) var captureRect: CGRect = .zero
    /// Called whenever `captureRect` changes.
    var onChange: (() -> Void)?
    /// True during `onChange` when the magnet moved the area with its window.
    private(set) var isFollowingWindow = false
    /// Called when the magnet turns off or lets go of its window.
    var onMagnetStopped: (() -> Void)?
    /// Called when the mouse moves anywhere on screen while the frame is shown.
    var onMouseMoved: (() -> Void)?
    /// Called by the frame's raise button: bring the Viewer forward.
    var onRaiseViewer: (() -> Void)?
    /// Called by the frame's pick button: pick a window for the area.
    var onPickWindow: (() -> Void)?
    /// Called when its window picker opens, for Fit to Window or the magnet.
    var onPickerStarted: (() -> Void)?
    /// Called when that picker closes, by a pick or a cancel.
    var onPickerEnded: (() -> Void)?

    /// The part of the area the Viewer shows, in AppKit global coordinates; `nil` while it shows the
    /// whole area, or nothing of it live. Outlined while the Viewer's image moves and while the cursor
    /// is near the frame.
    var viewedPart: CGRect? {
        didSet {
            guard viewedPart != oldValue else { return }
            updateViewedPartShown()
        }
    }

    /// A drag of the viewport handle started: the Viewer's pan it starts from.
    var onViewportHandleDragBegan: (() -> Void)?
    /// The viewport handle is dragged: how far the pointer moved since the drag began, in global
    /// points; the Viewer pans so the outline follows the pointer.
    var onViewportHandleDragged: ((CGVector) -> Void)?

    /// The width-to-height ratio a drag of a handle keeps, unless Shift squares the frame; `nil`
    /// resizes freely. The arrow keys don't keep it.
    var aspectRatio: CGFloat?

    /// A rect the position box never covers, in AppKit global coordinates: the studio's palette while
    /// it shows; `.null` for none.
    var positionAvoiding = CGRect.null {
        didSet { if positionAvoiding != oldValue { apply(captureRect, persist: false) } }
    }

    /// The rect's size in pixels of the display it is on, or `nil` when it is on no display.
    var pixelSize: PixelSize? {
        guard let converter, let display = converter.owningDisplay(for: GlobalRect(rect: captureRect)) else {
            return nil
        }
        return converter.pixelSize(of: captureRect.size, scale: display.scale)
    }

    /// The tab and the pick button beside it, in AppKit global coordinates, shown or not.
    var tabArea: CGRect? { layout.map { $0.tabRect.union($0.pickRect) } }

    /// What to capture for the current rect, or `nil` when it is on no display.
    var captureGeometry: CaptureGeometry? {
        converter?.captureGeometry(for: GlobalRect(rect: captureRect))
    }

    private let kind: OverlayFrameKind
    private let window = CaptureOverlayWindow()
    private let view: CaptureOverlayView
    /// The outline of the part the Viewer shows, click-through; the Capture Area's only.
    private let outline: ViewedPartOverlay?
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
    /// The viewport handle mode is on (`Settings.showsViewportHandle`): the outline stays and carries
    /// the handle.
    private var showsViewportHandle = false {
        didSet {
            updateViewedPartShown()
            // Its button leaves the collapsed buttons while the mode is on.
            if showsViewportHandle != oldValue { apply(captureRect, persist: false) }
        }
    }
    /// "»" was clicked: the buttons it collapses show in its place until the frame's buttons hide; the
    /// next reveal clears it.
    private var buttonsExpanded = false
    private var eventMonitors: [Any] = []
    /// Names the tab's button under the pointer.
    private lazy var buttonName = ButtonNameLabel(parent: window)
    /// The tab's button under the pointer as last seen, named or not. A click on it leaves it, so its
    /// name shows again only once the pointer has left it.
    private var pointedButton: OverlayHitTarget?
    private var keyObservers: [NSObjectProtocol] = []
    private var picker: WindowPicker?

    /// The window the magnet holds and where the area sits on it; `nil` while it holds none.
    private struct Magnet {
        /// As last read.
        var window: ScreenWindow
        /// `WindowMagnet.placement`: taken on attaching, after a resize or a move by the tab, and after
        /// the area followed its window's bounds.
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
    private var hasBeenShown = false

    private static let defaultSize = CGSize(width: 320, height: 200)
    /// The rect with nothing kept, from the main display's visible frame; `nil` for the Capture
    /// Area's own default.
    private let makeDefaultRect: ((CGRect) -> CGRect)?

    init(
        settings: SettingsStore, kind: OverlayFrameKind = .captureArea, defaultRect: ((CGRect) -> CGRect)? = nil
    ) {
        self.settings = settings
        self.kind = kind
        makeDefaultRect = defaultRect
        view = CaptureOverlayView(style: FrameStyle(settings.settings[keyPath: kind.style]), lockButtons: kind.hasLocks)
        outline = kind.hasLocks ? ViewedPartOverlay() : nil
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
        settings.observe(kind.style) { [weak self] in
            self?.view.style = FrameStyle($0)
            self?.outline?.style = FrameStyle($0)
        }
        settings.observe(\.sizeUnits) { [weak self] _ in
            guard let self else { return }
            apply(captureRect, persist: false)
        }
        guard kind.hasLocks else { return }
        // The magnet's window doesn't survive a relaunch: a Magnet mode comes up off.
        settings.update { if $0.captureAreaLock == .magnet { $0.captureAreaLocked = false } }
        settings.observe(\.captureAreaLock) { [weak self] in self?.view.lock = $0 }
        settings.observe(\.captureAreaLocked) { [weak self] in self?.view.isLocked = $0 }
        settings.observe(\.showsViewportHandle) { [weak self] in
            self?.view.isViewportHandleOn = $0
            self?.showsViewportHandle = $0
        }
        // The magnet turned off, or another lock chosen.
        settings.observe(\.activeCaptureAreaLock) { [weak self] in
            if $0 != .magnet { self?.stopMagnet() }
        }
    }

    // MARK: Visibility

    var isVisible: Bool { window.isVisible }

    /// The numbers of the frame's windows: its overlay and the outline's panel.
    var windowNumbers: [Int] { [window.windowNumber] + (outline.map { [$0.windowNumber] } ?? []) }

    func show() {
        if !hasBeenShown, kind.placedWhenFirstShown { apply(initialRect(), persist: false) }
        hasBeenShown = true
        window.orderFrontRegardless()
        outline?.order(.below, relativeTo: window.windowNumber)
        startMonitoringMouse()
    }

    /// A hidden area doesn't follow a window: the magnet turns off quietly, as at launch.
    func hide() {
        buttonName.end()
        pointedButton = nil
        window.orderOut(nil)
        outline?.orderOut(nil)
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
        apply(onScreen ? captureRect : defaultRect(), persist: hasBeenShown || !kind.placedWhenFirstShown)
    }

    private func refreshDisplays() {
        converter = DisplayLayout.current().map(DisplayCoordinateConverter.init(layout:))
    }

    private func initialRect() -> CGRect {
        if var saved = settings.settings[keyPath: kind.savedRect],
            converter?.owningDisplay(for: GlobalRect(rect: saved)) != nil
        {
            let minimum = CaptureAreaEditing.minimumSize
            saved.size = CGSize(width: max(saved.width, minimum.width), height: max(saved.height, minimum.height))
            return saved
        }
        return defaultRect()
    }

    private func defaultRect() -> CGRect {
        let screen =
            (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
        if let makeDefaultRect { return makeDefaultRect(screen) }
        let size = Self.defaultSize
        // Left of centre, so the Viewer fits beside it on first launch (docs/design.md §7, acceptance step 3).
        let centerX = screen.minX + screen.width * 0.3
        return CGRect(
            x: centerX - size.width / 2, y: screen.midY - size.height / 2, width: size.width, height: size.height)
    }

    // MARK: Sizes

    /// Gives the frame `size` pixels of the display it is on, keeping its top-left corner and
    /// staying on that display (`StudioSizes.frame`). A size the display can't hold, or one under the
    /// minimum, leaves the frame as it is and says why beside the tab.
    /// Returns whether it was applied.
    @discardableResult
    func resize(toPixels size: PixelSize) -> Bool {
        guard let display = converter?.owningDisplay(for: GlobalRect(rect: captureRect)) else { return false }
        switch StudioSizes.frame(captureRect, resizedTo: size, on: display, minimumSize: CaptureAreaEditing.minimumSize)
        {
        case .fits(let rect):
            applyEdited(rect, snap: .edges, persist: true)
            return true
        case .largerThanDisplay:
            showNotice("Larger than the display")
        case .smallerThanMinimum:
            showNotice("Smaller than 64 × 64 pt")
        }
        return false
    }

    /// Whether the rect lies wholly on the display that owns it.
    var isWhollyOnOneDisplay: Bool {
        converter?.isWhollyOnOneDisplay(GlobalRect(rect: captureRect)) ?? false
    }

    // MARK: Picking a window

    /// Lets the user pick a window, then makes the area that window, shown, and calls `onPicked`.
    /// Locked or not: the pin guards against a stray drag, and picking is a deliberate command. An
    /// attached magnet moves to the picked window.
    func pickWindow(onPicked: @escaping () -> Void) {
        pick(hint: "Click to fit the \(kind.name) · Esc to cancel") { [weak self] picked in
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

    /// Fit to Window's picker is open.
    var isPickingWindow: Bool { picker != nil }

    /// Closes Fit to Window's picker as a cancel.
    func stopPickingWindow() {
        picker?.stop()
    }

    /// Opens the window picker; `onPicked` runs only when a window is picked.
    private func pick(hint: String, onPicked: @escaping (ScreenWindow) -> Void) {
        guard picker == nil, let converter else { return }
        let picker = WindowPicker(
            windows: ScreenWindows.windows(converter: converter), tint: view.style.accent, hint: hint
        ) { [weak self] picked in
            self?.picker = nil
            self?.onPickerEnded?()
            if let picked { onPicked(picked) }
        }
        self.picker = picker
        // Started by a key or the menu with a name showing: it goes under the picker's panels.
        updateButtonName()
        onPickerStarted?()
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
        updateFitted()
        guard magnetTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.followMagnetWindow() }
        }
        // Also while a menu is open or a window is dragged.
        RunLoop.main.add(timer, forMode: .common)
        magnetTimer = timer
        // A window going full screen, or the user leaving for another Space.
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.letGoOfMagnetWindow() }
        }
    }

    /// Moves the area with its window, or lets go when the window is gone: onto the window's new
    /// bounds while it is fitted to them, else keeping its place on the window
    /// (`WindowMagnet.follow`). Waits out a drag of a handle or the tab: the window's change since then
    /// applies after it.
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
            isFollowingWindow = true
            switch WindowMagnet.follow(
                area: captureRect, placement: held.placement, from: held.window.frame, to: now.frame)
            {
            case .fitted(let rect):
                // Each edge on the pixels, as Fit to Window; the place on the window taken again, for
                // when the window grows past a minimum-size area, which is no longer fitted.
                applyEdited(rect, snap: .edges, persist: false)
                rememberMagnetPlacement()
            case .moved(let rect):
                apply(rect, persist: false)
            }
            isFollowingWindow = false
            magnetMoved = true
        } else if magnetMoved {
            // Saved once the window stops, not on every step of its move.
            magnetMoved = false
            settings.update { $0[keyPath: kind.savedRect] = captureRect }
        }
    }

    /// The window is gone: the area stays where it is, the magnet turns off and a notice says why.
    private func letGoOfMagnetWindow() {
        stopMagnet()
        settings.update { $0.captureAreaLocked = false }
        showNotice("Window gone · magnet off")
    }

    /// After a resize or a move by the tab, the area keeps its new size and place on the window.
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
        updateFitted()
        if magnetMoved {
            magnetMoved = false
            settings.update { $0[keyPath: kind.savedRect] = captureRect }
        }
        onMagnetStopped?()
    }

    // MARK: Notice

    /// Shows `text` beside the tab for a moment, then fades it.
    func showNotice(_ text: String) {
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
        let screenFrame = self.screenFrame(of: rect)
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
            positionAvoiding: positionAvoiding,
            noticeWidth: noticeText.map(OverlayStyle.labelWidth(for:)) ?? 0,
            lockButtons: kind.hasLocks,
            buttonsExpanded: buttonsExpanded,
            viewportHandleOn: showsViewportHandle
        )
        self.layout = layout
        window.setFrame(layout.windowFrame, display: false)
        view.update(layout: layout, tabText: tabText, labelText: labelText, positionLines: positionLines)
        updateViewedPartShown()

        if persist {
            settings.update { $0[keyPath: kind.savedRect] = rect }
        }
        // The row expanded or collapsed, or the frame moved under a still pointer.
        updateButtonName()
        updateFitted()
        onChange?()
    }

    /// The frame of the display that owns `rect`.
    private func screenFrame(of rect: CGRect) -> CGRect {
        converter?.owningDisplay(for: GlobalRect(rect: rect))?.globalFrame ?? NSScreen.main?.frame ?? rect
    }

    private func applyEdited(_ rect: CGRect, snap: Snap, persist: Bool) {
        // Resizing snaps each edge on its own, so the edges that don't move stay exactly in place;
        // `apply` then snaps as a whole, which leaves an already snapped rect unchanged.
        apply(snapped(rect, snap), persist: persist)
    }

    // MARK: Fitted

    /// The magnet holds a window and the area lies on its bounds (`WindowMagnet.isFitted`): the area
    /// follows the window's size too, and the window's own edges resize it.
    private var isFitted: Bool {
        magnet.map { WindowMagnet.isFitted(captureRect, to: $0.window.frame) } ?? false
    }

    /// While fitted, the frame's line lies on the window's edges: it has no handles, and its line is
    /// drawn by the click-through outline panel, so a press on it and the cursor go to the window
    /// underneath, whose own edges resize it. The overlay's panel takes a press on every drawn pixel,
    /// and setting its `ignoresMouseEvents` back to false would make it take one on every pixel.
    private func updateFitted() {
        view.isFitted = isFitted
        updateViewedPartShown()
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
        updateButtonName()
        onMouseMoved?()
    }

    /// Names the tab's button under the pointer while the buttons show (`ButtonNameLabel`), beside
    /// the row away from the frame (`OverlayLayout.buttonNameRect`); not during a drag nor while a
    /// window is picked. Called on every move of the pointer and every layout.
    private func updateButtonName() {
        let shown = isRevealed && drag == nil && picker == nil && window.isVisible
        let button = shown ? layout?.button(at: NSEvent.mouseLocation) : nil
        guard button != pointedButton else { return }
        if let pointedButton { buttonName.pointerExited(pointedButton) }
        pointedButton = button
        guard let button, let name = view.name(of: button) else { return }
        buttonName.pointerEntered(button, name: name) { [weak self] size in
            guard let self, let layout else { return nil }
            return layout.buttonNameRect(for: button, size: size, screenFrame: screenFrame(of: captureRect))
        }
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
        if !revealed { updateButtonName() }
        // The row expanded before the buttons last hid collapses as they show again, before they fade
        // in: collapsing as they hide would drop the raise and pick buttons mid-fade.
        if revealed, buttonsExpanded {
            buttonsExpanded = false
            apply(captureRect, persist: false)
        }
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

    /// With the viewport handle on, the outline stays, with the handle, and doesn't fade.
    private func updateViewedPartShown() {
        outline?.setShown(viewedPart != nil && (isNear || viewedPartTimer != nil || showsViewportHandle))
        if let layout {
            outline?.place(
                frame: layout.windowFrame, captureRect: layout.captureRect, viewedPart: viewedPart,
                drawsFrameLine: isFitted)
        }
        view.viewportHandleRect = viewportHandle
    }

    /// The viewport handle's rect, or `nil` while it isn't shown.
    private var viewportHandle: CGRect? {
        guard showsViewportHandle, let viewedPart, let layout else { return nil }
        return layout.viewportHandleRect(for: viewedPart, metrics: view.style.metrics)
    }
}

// MARK: - Mouse and keys

extension OverlayFrameController: CaptureOverlayViewDelegate {
    /// The studio's frame has no locks.
    private var lock: CaptureAreaLock? { kind.hasLocks ? settings.settings.activeCaptureAreaLock : nil }

    func overlayView(_ view: CaptureOverlayView, hitTargetAt point: CGPoint) -> OverlayHitTarget? {
        layout?.hitTarget(
            at: point, metrics: view.style.metrics, lock: lock, fitted: isFitted, viewportHandle: viewportHandle)
    }

    func overlayView(_ view: CaptureOverlayView, mouseDownAt point: CGPoint) {
        // A click hides the name; the button keeps it hidden until the pointer leaves it.
        buttonName.end()
        let target = self.overlayView(view, hitTargetAt: point)
        if target == .viewportButton {
            settings.update { $0.showsViewportHandle.toggle() }
            return
        }
        if target == .viewportHandle {
            drag = Drag(target: .viewportHandle, startMouse: point, startRect: captureRect)
            onViewportHandleDragBegan?()
            updateReveal()
            return
        }
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
        if target == .moreButtons {
            buttonsExpanded = true
            apply(captureRect, persist: false)
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
        // A locked frame takes only the handles its lock allows, and the magnet's frame its tab too, as
        // the hit test decided.
        // Otherwise the window only receives presses on its drawn pixels, and anything outside the
        // area that isn't a handle moves it. Inside, a press on no target does nothing.
        guard let target = target ?? (lock == nil && !captureRect.contains(point) ? .move : nil) else { return }
        drag = Drag(target: target, startMouse: point, startRect: captureRect)
        updateReveal()
    }

    func overlayView(_ view: CaptureOverlayView, mouseDraggedTo point: CGPoint) {
        guard let drag else { return }
        let delta = CGVector(dx: point.x - drag.startMouse.x, dy: point.y - drag.startMouse.y)
        if drag.target == .viewportHandle {
            onViewportHandleDragged?(delta)
            return
        }
        // With ⌘ held, edges snap to windows and displays (docs/product.md, Capture Area).
        let targets = NSEvent.modifierFlags.contains(.command) ? snapTargets() : []
        switch drag.target {
        case .move:
            let moved = EdgeSnapping.moved(drag.startRect.offsetBy(dx: delta.dx, dy: delta.dy), targets: targets)
            // The tab brought the magnet's area back onto its window: it lands on it, fitted again.
            if let window = magnet?.window.frame, let onto = WindowMagnet.snappedOnto(window, area: moved) {
                applyEdited(onto, snap: .edges, persist: false)
            } else {
                applyEdited(moved, snap: .move, persist: false)
            }
        case .resize(let handle):
            let resized = CaptureAreaEditing.resized(drag.startRect, handle: handle, by: delta)
            var rect = EdgeSnapping.resized(resized, handle: handle, targets: targets)
            // With Shift a corner keeps the area square, after ⌘-snapping: the longer side wins. Squared
            // after the pixel snap, so both sides come out the same whole number of pixels. Squared twice:
            // the square can end up owned by a display with another scale, whose grid the second pass uses.
            // Aspect Lock is fitted twice for the same reason, in whole pixels of the display that owns it.
            switch ResizeRule.forDrag(
                of: handle, shift: NSEvent.modifierFlags.contains(.shift), aspectRatio: aspectRatio)
            {
            case .free:
                break
            case .square:
                let square = CaptureAreaEditing.squared(snapped(rect, .edges), handle: handle)
                rect = CaptureAreaEditing.squared(snapped(square, .edges), handle: handle)
            case .aspect(let ratio):
                // On a corner, the side ⌘-snapping moved leads, so the snap holds.
                let lead = AspectLock.lead(resized: resized, snapped: rect)
                let minimum = CaptureAreaEditing.minimumSize
                let fitted = AspectLock.resized(
                    rect, handle: handle, ratio: ratio, scale: scale(of: rect), minimumSize: minimum, lead: lead)
                rect = AspectLock.resized(
                    rect, handle: handle, ratio: ratio, scale: scale(of: fitted), minimumSize: minimum, lead: lead)
            }
            applyEdited(rect, snap: .edges, persist: false)
        case .pin, .pinMenu, .viewportButton, .moreButtons, .raiseViewer, .pickWindow, .viewportHandle:
            break
        }
    }

    /// Pixels per point of the display that owns `rect`.
    private func scale(of rect: CGRect) -> CGFloat {
        converter?.owningDisplay(for: GlobalRect(rect: rect))?.scale ?? 1
    }

    /// Read once per drag: windows don't move while the frame is dragged.
    private func snapTargets() -> [CGRect] {
        if let targets = drag?.snapTargets { return targets }
        guard let converter else { return [] }
        let targets = ScreenWindows.frames(converter: converter) + converter.layout.displays.map(\.globalFrame)
        drag?.snapTargets = targets
        return targets
    }

    /// Not the viewport handle, and nothing else inside the area: the app underneath keeps the keyboard.
    func overlayView(_ view: CaptureOverlayView, takesKeyForPressAt point: CGPoint) -> Bool {
        let target = overlayView(view, hitTargetAt: point)
        return target != .viewportHandle && (target != nil || !captureRect.contains(point))
    }

    func overlayViewMouseUp(_ view: CaptureOverlayView) {
        guard let ended = drag else { return }
        drag = nil
        // The viewport handle moved the Viewer, not the area.
        if ended.target != .viewportHandle {
            rememberMagnetPlacement()
            settings.update { $0[keyPath: kind.savedRect] = captureRect }
        }
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

    func overlayViewPointerMoved(_ view: CaptureOverlayView) {
        updateButtonName()
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
