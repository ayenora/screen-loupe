import Carbon.HIToolbox
import MetalKit

extension MTKView {
    /// Drawable pixels per point: the unit `ZoomPanState` works in, over the view's points. Everything
    /// drawn over the image or exported from it converts with this.
    var drawableScale: CGFloat {
        bounds.width > 0 ? drawableSize.width / bounds.width : (window?.backingScaleFactor ?? 1)
    }
}

/// The magnified Capture Area. Draws only when a frame arrives or the zoom/pan changes.
///
/// Drawing is requested explicitly with `requestDraw()`. With MTKView's `setNeedsDisplay` mode
/// nothing was drawn any more after the window had been closed and reopened, while frames kept
/// arriving.
///
/// Pan: drag, two-finger scroll, horizontal scroll. Zoom around the cursor: pinch, ⌘ + wheel (or a
/// bare mouse wheel, per Settings), `+`/`-`; `0` fits (docs/product.md, Zoom and pan). With the Color Meter open the cursor is an eyedropper and a
/// click (without dragging) pins the colour under it. Option-drag copies a region; with the Select
/// tool on a drag selects and Space-drag pans (docs/product.md, Screenshots).
final class ViewerView: MTKView {
    private let frameStore: FrameStore
    private let zoomPan: ZoomPanController
    private let inspector: PixelInspector
    private var renderer: ViewerRenderer?

    /// Called when a click (not a drag) should pin the colour under the cursor.
    var onPick: (() -> Void)?

    /// The eyedropper cursor and click-to-pin, while the Color Meter is open.
    var isPicking = false {
        didSet { if isPicking != oldValue { window?.invalidateCursorRects(for: self) } }
    }

    var style: ViewerStyle {
        get { renderer?.style ?? ViewerStyle() }
        set {
            guard newValue != style else { return }
            renderer?.style = newValue
            clearColor = newValue.background.clearColor
            requestDraw()
        }
    }

    /// Off: a mouse wheel zooms without ⌘. Trackpad scrolling always pans.
    var wheelZoomNeedsCommand = true

    init(frameStore: FrameStore, zoomPan: ZoomPanController, inspector: PixelInspector) {
        self.frameStore = frameStore
        self.zoomPan = zoomPan
        self.inspector = inspector
        super.init(frame: .zero, device: MTLCreateSystemDefaultDevice())
        colorPixelFormat = ViewerRenderer.pixelFormat
        clearColor = ViewerBackground.dark.clearColor
        isPaused = true
        enableSetNeedsDisplay = false
        autoResizeDrawable = true
        // Until the next draw after a resize (the Color Meter opening, the window resizing), the
        // layer shows the old frame. Pinned to the top left instead of stretched, it matches the new
        // one, whose placement is kept from the top left too.
        layer?.contentsGravity = .topLeft
        renderer = ViewerRenderer(view: self, frameStore: frameStore, zoomPan: zoomPan)
        delegate = renderer
        renderer?.onTextureReady = { [weak self] in self?.requestDraw() }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var isDrawScheduled = false

    /// Draws once on the next turn of the main run loop, however many times it is asked before then.
    func requestDraw() {
        guard !isDrawScheduled else { return }
        isDrawScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            isDrawScheduled = false
            if window?.isVisible == true {
                draw()
            }
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        requestDraw()
    }

    /// A new frame is in the store.
    func frameArrived() {
        if let frame = frameStore.latestFrame {
            let geometry = frame.geometry
            let area = CGSize(width: geometry.areaSize.width, height: geometry.areaSize.height)
            let shift = resizeTracker.originShift(for: geometry)
            zoomPan.setContent(area, originShift: shift)
            selection?.areaOriginMoved(by: shift)
            matchColorSpace(ofDisplay: geometry.display.id)
        }
        requestDraw()
    }

    /// Copy View: what the Viewer shows now, rendered offscreen, with the pixel grid only when
    /// `showsGrid` (Settings › Screenshots). Tagged with the colour space the Viewer shows it in.
    /// Just `region` (viewport pixels) when given; else just the Select tool's selection while there
    /// is one, at the current zoom, even where it reaches beyond the viewport. Past `ImageBudget`
    /// only the top-left part. `nil` without a frame or without Metal.
    func renderViewImage(showsGrid: Bool, region: CGRect? = nil) -> CGImage? {
        guard let renderer else { return nil }
        var style = renderer.style
        style.showsGrid = style.showsGrid && showsGrid
        var scene = renderer.scene(for: self, style: style)
        if let region {
            scene.state.offset = CGPoint(x: scene.state.offset.x - region.minX, y: scene.state.offset.y - region.minY)
            scene.state.viewportSize = region.size
            scene.size = region.size
        } else if let rect = selection?.selection {
            scene.state = scene.state.cropped(to: rect)
            scene.size = scene.state.viewportSize
        }
        return renderer.renderImage(scene)
    }

    private var resizeTracker = AreaResizeTracker()

    /// The first live frame after a freeze keeps the framing (`AreaResizeTracker.forget`).
    func forgetAreaOrigin() {
        resizeTracker.forget()
    }

    private var colorSpaceDisplayID: CGDirectDisplayID?

    /// Frames come in the source display's color space (ScreenCaptureKit's default). Tagging the layer
    /// with it lets the system color-match when the Viewer sits on a display with another profile;
    /// on the same display the values pass through unchanged.
    private func matchColorSpace(ofDisplay displayID: CGDirectDisplayID) {
        guard displayID != colorSpaceDisplayID else { return }
        colorSpaceDisplayID = displayID
        colorspace = NSScreen.colorSpace(forDisplay: displayID)
    }

    // MARK: Coordinates

    /// A point in the view as a drawable pixel, y down: the space `ZoomPanState` works in.
    private func drawablePoint(_ point: CGPoint) -> CGPoint {
        let scale = drawableScale
        return CGPoint(x: point.x * scale, y: (bounds.height - point.y) * scale)
    }

    private func drawablePoint(_ event: NSEvent) -> CGPoint {
        drawablePoint(convert(event.locationInWindow, from: nil))
    }

    /// The cursor as a drawable pixel when it is over the view, for keyboard zoom around it.
    private var cursorPoint: CGPoint? {
        guard let window else { return nil }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard bounds.contains(point) else { return nil }
        return drawablePoint(point)
    }

    // MARK: Input

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The Select tool's crosshair, the eyedropper while the Color Meter is open, otherwise an open
    /// hand for panning.
    private var restingCursor: NSCursor {
        if isSpaceHeld { return .openHand }
        if selection?.isToolOn == true { return .crosshair }
        return isPicking ? .eyedropper : .openHand
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: restingCursor)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(
            NSTrackingArea(
                rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        inspectPixel(at: event)
        updateCursor(at: drawablePoint(event), modifiers: event.modifierFlags)
    }

    override func mouseExited(with event: NSEvent) {
        inspector.setViewerPixel(nil)
        ruler?.hover(at: nil, scale: drawableScale)
    }

    /// ⌥ turns the cursor into the region crosshair at once, without waiting for the mouse to move.
    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        if let point = cursorPoint { updateCursor(at: point, modifiers: event.modifierFlags) }
    }

    // MARK: Tools

    /// The corner ruler takes presses on its parts before the reference layers, and they before
    /// panning (docs/product.md, Ruler and References). An Option-drag comes before all of them,
    /// and the Select tool, while on, before the reference layers.
    var ruler: RulerController?
    var references: ReferencesController? {
        didSet {
            renderer?.references = { [weak references] in references?.drawable ?? [] }
        }
    }
    var selection: SelectionController?
    /// Called with an Option-drag's region, in viewport pixels, when the drag ends.
    var onCopyRegion: ((CGRect) -> Void)?

    private enum Press { case ruler, reference, selection }
    /// Who the current press belongs to; `nil` for panning or picking.
    private var toolPress: Press?

    private func updateCursor(at point: CGPoint, modifiers: NSEvent.ModifierFlags) {
        let scale = drawableScale
        if let ruler, ruler.isOn { ruler.hover(at: point, scale: scale) }
        if modifiers.contains(.option) || selection?.region != nil { return NSCursor.crosshair.set() }
        if isSpaceHeld { return restingCursor.set() }
        if let ruler, ruler.isOn,
            let cursor = RulerController.cursor(for: ruler.part(at: point, scale: scale), dragging: ruler.isDragging)
        {
            return cursor.set()
        }
        if let selection, selection.isToolOn {
            return SelectionController.cursor(for: selection.part(at: point, scale: scale)).set()
        }
        if let references,
            let cursor = ReferencesController.cursor(
                for: references.part(at: point, scale: scale), dragging: references.isDragging)
        {
            return cursor.set()
        }
        restingCursor.set()
    }

    /// Tells the inspector which Capture Area pixel is under the mouse.
    private func inspectPixel(at event: NSEvent) {
        let pixel = zoomPan.state.sourcePixel(atViewportPoint: drawablePoint(event))
        inspector.setViewerPixel(pixel)
    }

    // MARK: Mouse

    /// A press becomes a pan once the mouse moves this far; otherwise it is a click.
    private static let dragThreshold: CGFloat = 3
    private var pressLocation: CGPoint?
    private var isPanning = false

    override func mouseDown(with event: NSEvent) {
        let point = drawablePoint(event)
        let scale = drawableScale
        // Space let go while another window had the keyboard never reached `keyUp`.
        if isSpaceHeld, !CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_Space)) {
            isSpaceHeld = false
        }
        if isSpaceHeld {
            // Space-drag pans, whatever is under the mouse.
        } else if event.modifierFlags.contains(.option), let selection {
            selection.beginRegion(at: point)
            toolPress = .selection
            return
        } else if let ruler, ruler.press(at: point, scale: scale) {
            toolPress = .ruler
            updateCursor(at: point, modifiers: event.modifierFlags)
            return
        } else if let selection, selection.press(at: point, scale: scale) {
            toolPress = .selection
            return
        } else if let references, references.press(at: point, scale: scale) {
            toolPress = .reference
            updateCursor(at: point, modifiers: event.modifierFlags)
            return
        }
        pressLocation = event.locationInWindow
        isPanning = false
    }

    override func mouseDragged(with event: NSEvent) {
        switch toolPress {
        case .ruler?: return ruler?.drag(to: drawablePoint(event), scale: drawableScale) ?? ()
        case .reference?: return references?.drag(to: drawablePoint(event)) ?? ()
        case .selection?: return selection?.drag(to: drawablePoint(event), scale: drawableScale) ?? ()
        case nil: break
        }
        if !isPanning, let start = pressLocation {
            let moved = hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y)
            guard moved >= Self.dragThreshold else { return }
            isPanning = true
            spacePanned = isSpaceHeld
            NSCursor.closedHand.push()
            // Catch up with the distance covered before the pan started.
            let scale = drawableScale
            zoomPan.pan(
                by: CGPoint(
                    x: (event.locationInWindow.x - start.x) * scale, y: (start.y - event.locationInWindow.y) * scale))
            return
        }
        let scale = drawableScale
        zoomPan.pan(by: CGPoint(x: event.deltaX * scale, y: event.deltaY * scale))
        inspectPixel(at: event)
    }

    override func mouseUp(with event: NSEvent) {
        if let press = toolPress {
            toolPress = nil
            switch press {
            case .ruler: ruler?.endDrag()
            case .reference: references?.endDrag()
            case .selection: if let region = selection?.endDrag() { onCopyRegion?(region) }
            }
            updateCursor(at: drawablePoint(event), modifiers: event.modifierFlags)
            return
        }
        if isPanning {
            // Popping would bring back whatever was on the cursor stack (the arrow), not the cursor
            // of this view's cursor rect.
            NSCursor.pop()
            if bounds.contains(convert(event.locationInWindow, from: nil)) { restingCursor.set() }
        } else if isPicking, !isSpaceHeld, selection?.isToolOn != true {
            inspectPixel(at: event)
            onPick?()
        }
        pressLocation = nil
        isPanning = false
    }

    override func scrollWheel(with event: NSEvent) {
        let precise = event.hasPreciseScrollingDeltas
        // ⌘ + wheel zooms around the cursor; so does a bare wheel when Settings allows it, but a
        // horizontal wheel (or Shift + wheel) still pans.
        let wheelZooms = !wheelZoomNeedsCommand && !precise && event.scrollingDeltaY != 0
        if event.modifierFlags.contains(.command) || wheelZooms {
            let factor = exp(event.scrollingDeltaY * (precise ? 0.01 : 0.1))
            zoomPan.setZoom(zoomPan.state.zoom * factor, around: drawablePoint(event))
            return
        }
        let lines: CGFloat = precise ? 1 : 10
        let scale = drawableScale
        zoomPan.pan(by: CGPoint(x: event.scrollingDeltaX * lines * scale, y: event.scrollingDeltaY * lines * scale))
    }

    override func magnify(with event: NSEvent) {
        zoomPan.setZoom(zoomPan.state.zoom * (1 + event.magnification), around: drawablePoint(event))
    }

    // MARK: Keys

    /// Space is held with the Select tool on: a drag pans, and letting go freezes only if nothing
    /// was panned, as a tap of Space does anyway.
    private var isSpaceHeld = false
    private var spacePanned = false

    override func keyDown(with event: NSEvent) {
        switch event.charactersIgnoringModifiers {
        case "+", "=": zoomPan.stepZoom(1, around: cursorPoint)
        case "-", "_": zoomPan.stepZoom(-1, around: cursorPoint)
        case "0": zoomPan.fit()
        case " " where selection?.isToolOn == true:
            guard !event.isARepeat else { return }
            isSpaceHeld = true
            spacePanned = false
            restingCursor.set()
        case " ": sendToggleFreeze()
        case "\u{1b}":
            // Escape: drops the selection and stops a freeze countdown.
            selection?.clearSelection()
            NSApp.sendAction(#selector(AppController.cancelFreezeCountdown(_:)), to: nil, from: self)
        default: super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        guard event.charactersIgnoringModifiers == " ", isSpaceHeld else { return super.keyUp(with: event) }
        isSpaceHeld = false
        if !spacePanned { sendToggleFreeze() }
        if let point = cursorPoint { updateCursor(at: point, modifiers: event.modifierFlags) }
    }

    private func sendToggleFreeze() {
        NSApp.sendAction(#selector(AppController.toggleFreeze(_:)), to: nil, from: self)
    }
}
