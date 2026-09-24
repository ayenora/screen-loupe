import MetalKit

/// The magnified Capture Area. Draws only when a frame arrives or the zoom/pan changes.
///
/// Drawing is requested explicitly with `requestDraw()`. With MTKView's `setNeedsDisplay` mode
/// nothing was drawn any more after the window had been closed and reopened, while frames kept
/// arriving.
///
/// Pan: drag, two-finger scroll, horizontal scroll. Zoom around the cursor: pinch, ⌘ + wheel (or a
/// bare mouse wheel, per Settings), `+`/`-`; `0` fits (docs/product.md, Zoom and pan). With the Color Meter open the cursor is an eyedropper and a
/// click (without dragging) pins the colour under it.
final class ViewerView: MTKView {
    private let frameStore: FrameStore
    private let zoomPan: ZoomPanController
    private let inspector: PixelInspector
    private var renderer: ViewerRenderer?

    /// Called when a click (not a drag) should pin the colour under the cursor.
    var onPick: (() -> Void)?

    /// The eyedropper cursor and click-to-pin, while the Color Meter is open.
    var isPicking = false {
        didSet { window?.invalidateCursorRects(for: self) }
    }

    var style: ViewerStyle {
        get { renderer?.style ?? ViewerStyle() }
        set {
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
        colorPixelFormat = .bgra8Unorm
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
            zoomPan.setContent(area, originShift: originShift(for: geometry, size: area))
            matchColorSpace(ofDisplay: geometry.display.id)
        }
        requestDraw()
    }

    /// The last area's top-left corner, in pixels of its display, and that display.
    private var lastAreaOrigin: (display: CGDirectDisplayID, origin: CGPoint, size: CGSize)?

    /// How far the area's top-left corner moved, in source pixels, when the area was resized by its
    /// left or top edge. Zero for a move (the Viewer keeps its framing and shows the new place) and
    /// across displays.
    private func originShift(for geometry: CaptureGeometry, size: CGSize) -> CGPoint {
        let scale = geometry.display.scale
        let source = geometry.sourceRect.rect
        let origin = CGPoint(
            x: (source.minX * scale).rounded() - geometry.imageOrigin.x,
            y: (source.minY * scale).rounded() - geometry.imageOrigin.y)
        defer { lastAreaOrigin = (geometry.display.id, origin, size) }
        guard let last = lastAreaOrigin, last.display == geometry.display.id, last.size != size else {
            return .zero
        }
        return CGPoint(x: origin.x - last.origin.x, y: origin.y - last.origin.y)
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

    /// A window location as a drawable pixel, y down: the space `ZoomPanState` works in.
    private func drawablePoint(_ event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        let scale = drawableScale
        return CGPoint(x: point.x * scale, y: (bounds.height - point.y) * scale)
    }

    /// The cursor as a drawable pixel when it is over the view, for keyboard zoom around it.
    private var cursorPoint: CGPoint? {
        guard let window else { return nil }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard bounds.contains(point) else { return nil }
        let scale = drawableScale
        return CGPoint(x: point.x * scale, y: (bounds.height - point.y) * scale)
    }

    var drawableScale: CGFloat {
        bounds.width > 0 ? drawableSize.width / bounds.width : (window?.backingScaleFactor ?? 1)
    }

    // MARK: Input

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The eyedropper while the Color Meter is open, otherwise an open hand for panning.
    private var restingCursor: NSCursor { isPicking ? .eyedropper : .openHand }

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
    }

    override func mouseExited(with event: NSEvent) {
        inspector.setViewerPixel(nil)
    }

    /// Tells the inspector which Capture Area pixel is under the mouse.
    private func inspectPixel(at event: NSEvent) {
        let pixel = zoomPan.state.sourcePixel(atViewportPoint: drawablePoint(event))
        inspector.setViewerPixel(pixel)
    }

    /// A press becomes a pan once the mouse moves this far; otherwise it is a click.
    private static let dragThreshold: CGFloat = 3
    private var pressLocation: CGPoint?
    private var isPanning = false

    override func mouseDown(with event: NSEvent) {
        pressLocation = event.locationInWindow
        isPanning = false
    }

    override func mouseDragged(with event: NSEvent) {
        if !isPanning, let start = pressLocation {
            let moved = hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y)
            guard moved >= Self.dragThreshold else { return }
            isPanning = true
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
        if isPanning {
            // Popping would bring back whatever was on the cursor stack (the arrow), not the cursor
            // of this view's cursor rect.
            NSCursor.pop()
            if bounds.contains(convert(event.locationInWindow, from: nil)) { restingCursor.set() }
        } else if isPicking {
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

    override func keyDown(with event: NSEvent) {
        switch event.charactersIgnoringModifiers {
        case "+", "=": zoomPan.stepZoom(1, around: cursorPoint)
        case "-", "_": zoomPan.stepZoom(-1, around: cursorPoint)
        case "0": zoomPan.fit()
        default: super.keyDown(with: event)
        }
    }
}
