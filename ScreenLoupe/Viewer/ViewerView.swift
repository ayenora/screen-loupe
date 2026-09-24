import MetalKit

/// The magnified Capture Area. Draws only when a frame arrives or the zoom/pan changes.
///
/// Drawing is requested explicitly with `requestDraw()`. With MTKView's `setNeedsDisplay` mode
/// nothing was drawn any more after the window had been closed and reopened, while frames kept
/// arriving.
///
/// Pan: drag, two-finger scroll, horizontal scroll. Zoom around the cursor: pinch, ⌘ + wheel,
/// `+`/`-`; `0` fits (TASK.md §4–§6).
final class ViewerView: MTKView {
    private let frameStore: FrameStore
    private let zoomPan: ZoomPanController
    private var renderer: ViewerRenderer?

    init(frameStore: FrameStore, zoomPan: ZoomPanController) {
        self.frameStore = frameStore
        self.zoomPan = zoomPan
        super.init(frame: .zero, device: MTLCreateSystemDefaultDevice())
        colorPixelFormat = .bgra8Unorm
        clearColor = ViewerRenderer.backgroundColor
        isPaused = true
        enableSetNeedsDisplay = false
        autoResizeDrawable = true
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
            let area = frame.geometry.areaSize
            zoomPan.setContent(CGSize(width: area.width, height: area.height))
        }
        requestDraw()
    }

    // MARK: Coordinates

    /// A window location as a drawable pixel, y down: the space `ZoomPanState` works in.
    private func drawablePoint(_ event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        let scale = drawableScale
        return CGPoint(x: point.x * scale, y: (bounds.height - point.y) * scale)
    }

    private var drawableScale: CGFloat {
        bounds.width > 0 ? drawableSize.width / bounds.width : (window?.backingScaleFactor ?? 1)
    }

    // MARK: Input

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        NSCursor.closedHand.push()
    }

    override func mouseDragged(with event: NSEvent) {
        let scale = drawableScale
        zoomPan.pan(by: CGPoint(x: event.deltaX * scale, y: event.deltaY * scale))
    }

    override func mouseUp(with event: NSEvent) {
        NSCursor.pop()
    }

    override func scrollWheel(with event: NSEvent) {
        let precise = event.hasPreciseScrollingDeltas
        if event.modifierFlags.contains(.command) {
            // ⌘ + wheel zooms around the cursor.
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
        case "+", "=": zoomPan.stepZoom(1)
        case "-", "_": zoomPan.stepZoom(-1)
        case "0": zoomPan.fit()
        default: super.keyDown(with: event)
        }
    }
}
