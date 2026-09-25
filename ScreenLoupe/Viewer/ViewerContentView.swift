import AppKit
import SwiftUI

/// The Viewer's content while it shows the capture: the magnified image with the overlay, the
/// frozen indicator, the status panel and the toast over it, and the side column (Color Meter,
/// References or Recent Captures) at its right. What happens inside it is wired here; the window
/// controller only places it.
@MainActor
final class ViewerContentView: NSStackView {
    let viewerView: ViewerView
    let statusView = CaptureStatusView()
    let ruler: RulerController
    let selection: SelectionController
    let captures = RecentCaptures()
    /// Called when a recent capture starts or stops showing in place of the live view.
    var onShowCapture: (() -> Void)?

    private let settings: SettingsStore
    private let frameStore: FrameStore
    private let zoomPan: ZoomPanController
    private let inspector: PixelInspector
    private let overlay: ViewerOverlayView
    private let meterPanel: ColorMeterPanel
    private let references: ReferencesController
    private let sidePanels: SidePanelStack
    private let toast = ToastView()
    private let frozenIndicator = FrozenIndicatorView()
    private let captureIndicator = FrozenIndicatorView()
    /// The live view's zoom, pan and selection while a recent capture shows, to go back to.
    private var liveView: (zoom: CGFloat, offset: CGPoint, selection: CGRect?)?
    /// The magnified image with everything drawn over it; left of the side column.
    private let imageArea = NSView()
    /// The side panels as last set, for the modes of the mouse in the image.
    private var sidePanelLayout: SidePanelLayout?

    init(
        settings: SettingsStore, frameStore: FrameStore, zoomPan: ZoomPanController, inspector: PixelInspector,
        project: ProjectStore
    ) {
        self.settings = settings
        self.frameStore = frameStore
        self.zoomPan = zoomPan
        self.inspector = inspector
        let viewerView = ViewerView(frameStore: frameStore, zoomPan: zoomPan, inspector: inspector)
        self.viewerView = viewerView
        overlay = ViewerOverlayView(zoomPan: zoomPan, inspector: inspector)
        overlay.drawableScale = { [weak viewerView] in viewerView?.drawableScale ?? 1 }
        overlay.sourceScale = { frameStore.latestFrame?.geometry.display.scale ?? 1 }
        meterPanel = ColorMeterPanel(inspector: inspector)
        ruler = RulerController(zoomPan: zoomPan, project: project)
        references = ReferencesController(project: project, zoomPan: zoomPan)
        selection = SelectionController(zoomPan: zoomPan)
        viewerView.ruler = ruler
        overlay.ruler = ruler
        viewerView.selection = selection
        overlay.selection = selection
        viewerView.references = references
        overlay.references = references
        let referencesPanel = NSHostingView(rootView: ReferencesPanel(references: references))
        // The side panel column sizes it, not its content.
        referencesPanel.sizingOptions = []
        let capturesPanel = NSHostingView(rootView: RecentCapturesPanel(captures: captures))
        capturesPanel.sizingOptions = []
        sidePanels = SidePanelStack(meter: meterPanel, references: referencesPanel, captures: capturesPanel)
        super.init(frame: .zero)
        build()
        wire(zoomPan: zoomPan)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func build() {
        // Views don't clip by default since macOS 14; the reference frame and the ruler would draw
        // over the side panels.
        imageArea.clipsToBounds = true
        frozenIndicator.isHidden = true
        captureIndicator.isHidden = true
        for view in [viewerView, overlay, frozenIndicator, captureIndicator] as [NSView] {
            view.frame = imageArea.bounds
            view.autoresizingMask = [.width, .height]
            imageArea.addSubview(view)
        }
        statusView.isHidden = true
        statusView.translatesAutoresizingMaskIntoConstraints = false
        imageArea.addSubview(statusView)
        toast.translatesAutoresizingMaskIntoConstraints = false
        imageArea.addSubview(toast)
        NSLayoutConstraint.activate([
            statusView.centerXAnchor.constraint(equalTo: imageArea.centerXAnchor),
            statusView.centerYAnchor.constraint(equalTo: imageArea.centerYAnchor),
            toast.centerXAnchor.constraint(equalTo: imageArea.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: imageArea.bottomAnchor, constant: -16),
        ])
        imageArea.setContentHuggingPriority(.defaultLow, for: .horizontal)
        orientation = .horizontal
        spacing = 0
        alignment = .height
        distribution = .fill
        addArrangedSubview(imageArea)
        addArrangedSubview(sidePanels)
    }

    private func wire(zoomPan: ZoomPanController) {
        zoomPan.observe { [weak self] in
            guard let self else { return }
            viewerView.requestDraw()
            overlay.needsDisplay = true
            ruler.viewportChanged()
        }
        ruler.observe { [weak self] in self?.overlay.needsDisplay = true }
        selection.observe { [weak self] in
            self?.overlay.needsDisplay = true
            self?.applyMouseModes()
        }
        viewerView.onCopyRegion = { [weak self] region in self?.copyRegion(region) }
        viewerView.onShowLive = { [weak self] in self?.captures.show(nil) }
        captures.onShow = { [weak self] old, new in self?.show(new, after: old) }
        captures.onChange = { [weak self] in self?.showCaptureIndicator() }
        inspector.onChange = { [weak self] in
            self?.overlay.needsDisplay = true
            self?.meterPanel.refresh()
        }
        references.onChange = { [weak self] in
            self?.viewerView.requestDraw()
            self?.overlay.needsDisplay = true
        }
        viewerView.onPick = { [weak self] in self?.pickColor() }
        meterPanel.onCopy = { [weak self] text, what in self?.copyText(text, what: what) }

        let settings = settings
        sidePanels.onExpand = { panel in settings.update { $0.expandedSidePanel = panel } }
        sidePanels.onScale = { [weak references, captures] scale in
            references?.scale = scale
            captures.scale = scale
        }
        sidePanels.width = CGFloat(settings.settings.sidePanelWidth)
        sidePanels.onResize = { width in settings.update { $0.sidePanelWidth = Double(width) } }

        // Settings › Viewer and the toolbar's toggles.
        settings.observe(\.viewerStyle) { [weak self] in self?.viewerView.style = $0 }
        settings.observe(\.wheelZoomNeedsCommand) { [weak self] in self?.viewerView.wheelZoomNeedsCommand = $0 }
        settings.observe(\.crosshairEnabled) { [weak self] in self?.overlay.showsCrosshair = $0 }
        settings.observe(\.pointerStyle) { [weak self] in self?.overlay.pointerStyle = $0 }
        settings.observe(\.crosshairColor) { [weak self] in self?.overlay.color = $0.nsColor }
        settings.observe(\.sidePanelLayout) { [weak self] layout in
            guard let self else { return }
            sidePanels.show(layout)
            references.isActive = layout.showsReferences
            // Closing Recent Captures goes back to live.
            if !layout.showsCaptures { captures.show(nil) }
            sidePanelLayout = layout
            applyMouseModes()
        }
    }

    /// Who the mouse in the image belongs to. The Select tool comes first; else the eyedropper,
    /// which works only while the Color Meter is expanded; reference layers take it when neither does.
    private func applyMouseModes() {
        let isSelecting = selection.isToolOn
        viewerView.isPicking = !isSelecting && sidePanelLayout?.isMeterExpanded == true
        references.takesMouse = !isSelecting && !viewerView.isPicking
        window?.invalidateCursorRects(for: viewerView)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        references.window = window
    }

    /// The size of the image area, without the side column.
    var imageAreaSize: CGSize { imageArea.frame.size }

    /// A short confirmation at the bottom of the image, such as "View copied".
    func showToast(_ text: String) {
        toast.show(text)
    }

    /// Frozen, counting down to a freeze, or live.
    func showFreeze(_ state: FrozenIndicatorView.State) {
        // The first live frame after a freeze keeps the framing (`AreaResizeTracker.forget`).
        if frozenIndicator.state.isFrozen, !state.isFrozen { viewerView.forgetAreaOrigin() }
        frozenIndicator.state = state
    }

    /// An Option-drag's region, straight to the clipboard.
    private func copyRegion(_ region: CGRect) {
        guard let image = viewerView.renderViewImage(showsGrid: settings.settings.gridInCopyView, region: region),
            ScreenshotExporter.copy(image)
        else { return NSSound.beep() }
        captureKeeper(.region, image: image)?()
        showToast("Region copied")
    }

    // MARK: Recent Captures

    /// Whether a recent capture shows in place of the live view.
    var isShowingCapture: Bool { captures.shownID != nil }

    /// What a copy or save was made of, for its recent capture.
    enum CaptureKind {
        case view, source, region
    }

    /// Keeps the picture `image` was just made from as a recent capture (docs/product.md, Recent
    /// Captures): the returned call adds it, now for a copy, once written for a save. The frame and
    /// how the Viewer shows it are taken now. `nil` while a recent capture shows: copies made from
    /// one add none.
    func captureKeeper(_ kind: CaptureKind, image: CGImage) -> (() -> Void)? {
        guard !isShowingCapture, let frame = frameStore.latestFrame else { return nil }
        let state = zoomPan.state
        let name =
            switch kind {
            case .view: selection.selection != nil ? "Selection" : "View · \(Int((state.zoom * 100).rounded()))%"
            case .source: "Source"
            case .region: "Region"
            }
        guard
            let capture = RecentCaptures.capture(
                of: frame, kind: name, image: image, zoom: state.zoom, offset: state.offset,
                selection: selection.keptSelection)
        else { return nil }
        return { [weak self] in self?.captures.add(capture) }
    }

    /// Shows `new` in place of `old` (`nil`: the live view). Each keeps its zoom, pan and selection:
    /// they are put away and brought back, so going back finds everything as it was left.
    private func show(_ new: RecentCapture?, after old: RecentCapture?) {
        let state = zoomPan.state
        if let old {
            captures.keep(old.id, zoom: state.zoom, offset: state.offset, selection: selection.keptSelection)
        } else {
            liveView = (state.zoom, state.offset, selection.keptSelection)
        }
        frameStore.shownCapture = new?.frame
        // The next picture is not an edge drag of the last one.
        viewerView.forgetAreaOrigin()
        viewerView.frameArrived()
        if let new {
            zoomPan.restore(zoom: new.zoom, offset: new.offset)
            selection.keptSelection = new.selection
        } else if let live = liveView {
            zoomPan.restore(zoom: live.zoom, offset: live.offset)
            selection.keptSelection = live.selection
            liveView = nil
        }
        inspector.frameArrived()
        showCaptureIndicator()
        onShowCapture?()
    }

    /// The purple border and "Capture 2 of 4 · 14:20:05 · Esc for live" while a capture shows; the
    /// frozen indicator of the live view waits under it.
    private func showCaptureIndicator() {
        let shown = captures.shown
        captureIndicator.state = shown.map { .capture(label: captures.label(for: $0)) } ?? .hidden
        frozenIndicator.alphaValue = shown == nil ? 1 : 0
    }

    private func pickColor() {
        guard let pin = inspector.pinProbe() else { return }
        showToast("Pinned \(pin.hex)")
    }

    private func copyText(_ text: String, what: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        showToast("Copied \(what)")
    }
}
