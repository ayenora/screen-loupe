import AppKit
import VisionKit

/// Copy Text: the text of the still picture the Viewer shows, read by VisionKit and selected with
/// the mouse over the image, as Live Text works in Preview. The system's text layer
/// (`ImageAnalysisOverlayView`) sits over the frame's pixels as they show (`CopyText.overlayFrame`)
/// and only while the mode is on, so the mouse is the other tools' the rest of the time. What
/// turns the mode on and off is `CopyTextMode`; `ViewerContentView` carries out its steps.
@MainActor
final class CopyTextController: NSObject, ImageAnalysisOverlayViewDelegate {
    /// Over the image area, under the indicators; holds the text layer.
    let host: CopyTextHost
    private let overlay = ImageAnalysisOverlayView()
    private let analyzer = ImageAnalyzer()
    private var analysis: Task<Void, Never>?
    /// The pixels read last, so the same picture isn't read twice.
    private var readBuffer: (buffer: CVPixelBuffer, rect: PixelRect)?
    private var observers: [() -> Void] = []

    var mode = CopyTextMode() {
        didSet { if mode.isOn != oldValue.isOn { observers.forEach { $0() } } }
    }

    var isOn: Bool { mode.isOn }

    /// Called with `CopyText.unreadable` when a picture can't be read: Live Text isn't supported on
    /// this Mac, or reading it failed. Once a picture, since a picture read before isn't read again.
    var onUnreadable: ((String) -> Void)?

    init(viewerView: ViewerView) {
        host = CopyTextHost(viewerView: viewerView)
        super.init()
        host.isHidden = true
        host.addSubview(overlay)
        overlay.delegate = self
        overlay.preferredInteractionTypes = .textSelection
        // No hints over the text: the system's I-beam shows where it is.
        overlay.selectableItemsHighlighted = false
        overlay.setSupplementaryInterfaceHidden(true, animated: false)
    }

    /// Calls `observer` when the mode turns on or off.
    func observe(_ observer: @escaping () -> Void) {
        observers.append(observer)
    }

    /// Puts the text layer over `frame`'s pixels, read off the main thread; a picture read before
    /// keeps its text. A reading still going on for another picture is dropped. Nothing while the
    /// mode is off: the layer would take the mouse.
    func show(_ frame: ViewerFrame?) {
        guard isOn else { return }
        host.isHidden = false
        guard let frame else { return clear() }
        guard frame.pixelBuffer !== readBuffer?.buffer || frame.bufferRect != readBuffer?.rect else { return }
        clear()
        readBuffer = (frame.pixelBuffer, frame.bufferRect)
        guard ImageAnalyzer.isSupported else {
            onUnreadable?(CopyText.unreadable)
            return
        }
        let colorSpace = frame.colorSpace
        let analyzer = analyzer
        analysis = Task { [weak self] in
            let image = await Task.detached(priority: .userInitiated) {
                ScreenshotExporter.frameImage(frame, colorSpace: colorSpace)
            }.value
            guard let image, !Task.isCancelled else { return }
            let read: ImageAnalysis
            do {
                read = try await analyzer.analyze(
                    image, orientation: .up, configuration: ImageAnalyzer.Configuration(.text))
            } catch {
                guard let self, !Task.isCancelled else { return }
                onUnreadable?(CopyText.unreadable)
                return
            }
            guard let self, !Task.isCancelled else { return }
            overlay.analysis = read
        }
    }

    /// Takes the text layer away and stops reading.
    func hide() {
        clear()
        host.isHidden = true
    }

    private func clear() {
        analysis?.cancel()
        analysis = nil
        readBuffer = nil
        overlay.analysis = nil
    }

    /// The text layer's frame in the image area's points, y down (`CopyText.overlayFrame`).
    func place(_ frame: CGRect) {
        guard overlay.frame != frame else { return }
        overlay.frame = frame
    }

    /// The selected text, or `nil` while none is selected.
    var selectedText: String? {
        overlay.hasActiveTextSelection ? overlay.selectedText : nil
    }

    var hasTextSelection: Bool { overlay.hasActiveTextSelection }

    func clearTextSelection() {
        overlay.resetSelection()
    }

    /// Edit › Select All Text: all the text read in the picture; nothing before it is read.
    func selectAllText() {
        let text = overlay.text
        guard !text.isEmpty else { return }
        overlay.selectedRanges = [text.startIndex..<text.endIndex]
    }

    // MARK: ImageAnalysisOverlayViewDelegate

    /// The layer is laid over the frame's pixels exactly: the image fills it.
    func contentsRect(for overlayView: ImageAnalysisOverlayView) -> CGRect {
        CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    /// Keys are the Viewer's: Escape, Space, zoom and ⌘C work as `ViewerView` and the menus say
    /// (`CopyTextHost` gives the keyboard back to the image).
    func overlayView(_ overlayView: ImageAnalysisOverlayView, shouldHandleKeyDownEvent event: NSEvent) -> Bool {
        false
    }
}

/// The text layer's superview, the size of the image area, y down as zoom and pan are. Only the
/// layer takes the mouse; elsewhere it falls to the Viewer's image, which pans. Scrolling and
/// pinching over the layer zoom and pan the image as they do without it.
///
/// A click in the layer makes VisionKit's text view the window's first responder, and the keys
/// it declines then go up through this view, never reaching the Viewer's image: Escape, Space and
/// the zoom keys did nothing, and ⌘C copied through VisionKit rather than `AppController`. So the
/// keyboard goes back to the image whenever a view in here takes it; the text selection stays.
final class CopyTextHost: NSView {
    private weak var viewerView: ViewerView?
    private var firstResponderObservation: NSKeyValueObservation?

    init(viewerView: ViewerView) {
        self.viewerView = viewerView
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        firstResponderObservation = window?.observe(\.firstResponder) { [weak self] window, _ in
            MainActor.assumeIsolated { self?.keepKeyboard(in: window) }
        }
    }

    private func keepKeyboard(in window: NSWindow) {
        guard let viewerView, let view = window.firstResponder as? NSView, view.isDescendant(of: self) else {
            return
        }
        window.makeFirstResponder(viewerView)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    override func scrollWheel(with event: NSEvent) {
        viewerView?.scrollWheel(with: event)
    }

    override func magnify(with event: NSEvent) {
        viewerView?.magnify(with: event)
    }
}
