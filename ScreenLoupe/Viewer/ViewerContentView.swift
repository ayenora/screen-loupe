import AppKit
import SwiftUI

/// The Viewer's content while it shows the capture: the magnified image with the overlay, the
/// frozen indicator, the status panel and the toast over it, and the side column (Color Meter,
/// References or Recent Captures) at its right. Image files dropped on it become reference layers
/// or recent captures (`dropTarget`). What happens inside it is wired here; the window controller
/// only places it.
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
        meterPanel = ColorMeterPanel(inspector: inspector)
        ruler = RulerController(zoomPan: zoomPan, project: project)
        ruler.sourceScale = { frameStore.shownFrame?.layout.scale ?? 1 }
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
        wantsLayer = true
        registerForDraggedTypes([.fileURL])
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
        captureKeeper(.region(region), image: image)?()
        showToast("Region copied")
    }

    // MARK: Dropped image files

    /// Where dropped image files go (docs/product.md, Dropping images).
    private enum DropTarget {
        /// Reference layers: the References panel is open.
        case references
        /// Recent captures, to inspect: Recent Captures is open.
        case captures
        /// Asked in a menu at the drop point: neither panel is open.
        case ask
    }

    private var dropTarget: DropTarget {
        if sidePanelLayout?.showsReferences == true { return .references }
        if sidePanelLayout?.showsCaptures == true { return .captures }
        return .ask
    }

    /// Whether a drag is over the content and would be taken; its border shows then.
    private var isDropTargeted = false {
        didSet { needsDisplay = true }
    }
    /// Counts image files asked for, by Open Image or a drop, so only the latest request shows;
    /// closing the Viewer counts too.
    private(set) var imageRequest = 0

    /// The border is the layer's, which Core Animation draws over the Metal image and every view
    /// in the content, not filled in `draw(_:)` (see the Color Meter's note on the Metal layer).
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.borderWidth = isDropTargeted ? 3 : 0
    }

    /// The dragged files of the types Open Image and Add… take; the rest are ignored.
    private func imageURLs(_ info: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: ImageFileLoader.openableTypes.map(\.identifier),
        ]
        return info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
    }

    /// Text, web links and other files are refused, and so are references with the stack full.
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isDropTargeted =
            !imageURLs(sender).isEmpty && (dropTarget != .references || references.stack.canAdd)
        return isDropTargeted ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDropTargeted = false
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        isDropTargeted = false
    }

    /// Takes the files; where they go is decided on the next turn of the run loop, so the menu
    /// that may ask comes up after the drag has ended.
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDropTargeted = false
        let urls = imageURLs(sender)
        guard !urls.isEmpty else { return false }
        let point = convert(sender.draggingLocation, from: nil)
        DispatchQueue.main.async { [weak self] in self?.place(urls, askingAt: point) }
        return true
    }

    private func place(_ urls: [URL], askingAt point: CGPoint) {
        switch dropTarget {
        case .references:
            addReferences(urls)
        case .captures:
            inspect(urls)
        case .ask:
            let menu = NSMenu()
            menu.autoenablesItems = false
            let add = menu.addItem(
                withTitle: "Add as Reference", action: #selector(placeDroppedFiles(_:)), keyEquivalent: "")
            add.isEnabled = references.stack.canAdd
            menu.addItem(withTitle: "Open for Inspection", action: #selector(placeDroppedFiles(_:)), keyEquivalent: "")
                .tag = 1
            for item in menu.items {
                item.target = self
                item.representedObject = urls
            }
            menu.popUp(positioning: nil, at: point, in: self)
        }
    }

    @objc private func placeDroppedFiles(_ item: NSMenuItem) {
        guard let urls = item.representedObject as? [URL] else { return }
        if item.tag == 0 {
            addReferences(urls)
        } else {
            inspect(urls)
        }
    }

    /// Adds image files as reference layers, as Add… does, and opens the References panel on them
    /// as its toolbar button does. When none could be added, says so.
    private func addReferences(_ urls: [URL]) {
        let count = references.stack.layers.count
        let failed = references.add(urls)
        guard references.stack.layers.count > count else {
            // Nothing failed: the stack filled up after the drag came in.
            if !failed.isEmpty { showFailure(failed, verb: "added") }
            return
        }
        settings.update {
            $0.referencesVisible = true
            $0.capturesVisible = false
            $0.expandedSidePanel = .references
        }
    }

    /// Decodes image files off the main thread and keeps each as a recent capture, in order, the last
    /// one shown, as Open Image does; only as many as the list keeps. The rows are added once all are
    /// read, so the Viewer shows the last one only, not each in turn. When none could be read, says so.
    private func inspect(_ urls: [URL]) {
        let urls = Array(urls.suffix(RecentCaptures.limit))
        let request = newImageRequest()
        Task {
            var failed: [URL] = []
            var read: [RecentCapture] = []
            for url in urls {
                let decoded = await ImageFileLoader.frame(at: url)
                // A later file was asked for, or the Viewer has closed.
                guard request == imageRequest else { return }
                guard let decoded else {
                    failed.append(url)
                    continue
                }
                read.append(
                    RecentCaptures.file(decoded.frame, thumbnail: decoded.thumbnail, name: url.lastPathComponent))
            }
            guard let last = read.last else { return showFailure(failed, verb: "opened") }
            read.dropLast().forEach(captures.add)
            showFile(last)
        }
    }

    /// "The image couldn't be added." or "…opened.", naming the files.
    private func showFailure(_ files: [URL], verb: String) {
        let alert = NSAlert()
        alert.messageText = files.count == 1 ? "The image couldn't be \(verb)." : "The images couldn't be \(verb)."
        alert.informativeText = files.map(\.lastPathComponent).joined(separator: ", ")
        if let window { alert.beginSheetModal(for: window) }
    }

    /// A new request for an image file to show, which overtakes the ones before.
    @discardableResult
    func newImageRequest() -> Int {
        imageRequest += 1
        return imageRequest
    }

    // MARK: Recent Captures

    /// Whether a recent capture shows in place of the live view.
    var isShowingCapture: Bool { captures.shownID != nil }

    /// Keeps an image file as the newest recent capture and shows it in place of the live view
    /// (docs/product.md, Open Image), fitted to the Viewer (`show`), with Recent Captures open.
    /// `name` is its file's.
    func showImage(_ frame: ViewerFrame, thumbnail: CGImage?, name: String) {
        showFile(RecentCaptures.file(frame, thumbnail: thumbnail, name: name))
    }

    /// Keeps `capture`, an image file's, as the newest recent capture and shows it (`showImage`).
    private func showFile(_ capture: RecentCapture) {
        settings.update {
            $0.capturesVisible = true
            $0.referencesVisible = false
            $0.expandedSidePanel = .captures
        }
        captures.add(capture)
        captures.show(capture.id)
    }

    /// What a copy or save was made of, for its recent capture.
    enum CaptureKind: Equatable {
        case view, source
        /// An Option-drag's region, in viewport pixels.
        case region(CGRect)
    }

    /// Keeps the picture `image` was just made from as a recent capture (docs/product.md, Recent
    /// Captures): the returned call adds it, now for a copy, once written for a save. The frame and
    /// how the Viewer shows it are taken now; a view, a selection or a region keeps just its pixels,
    /// framed as it was, and only a source copy keeps the whole area. `nil` while a recent capture shows: copies made from one add none.
    func captureKeeper(_ kind: CaptureKind, image: CGImage) -> (() -> Void)? {
        guard !isShowingCapture, let frame = frameStore.shownFrame else { return nil }
        let state = zoomPan.state
        let name: String
        let area: CGRect?
        switch kind {
        case .view:
            // The selection, or else the source pixels the window shows, as an Option-drag over it.
            let selected = selection.selection
            area =
                selected ?? ViewRegion.sourceRect(of: CGRect(origin: .zero, size: state.viewportSize), in: state)
            name = selected != nil ? "Selection" : "View · \(Int((state.zoom * 100).rounded()))%"
            guard area != nil else { return nil }
        case .source:
            area = nil
            name = "Source"
        case .region(let region):
            area = ViewRegion.sourceRect(of: region, in: state)
            name = "Region"
            guard area != nil else { return nil }
        }
        // A cut picture starts at the area's corner: the same pixels stay where they were.
        let origin = area?.origin ?? .zero
        let offset = CGPoint(x: state.offset.x + origin.x * state.zoom, y: state.offset.y + origin.y * state.zoom)
        guard
            let capture = RecentCaptures.capture(
                of: frame, area: area, kind: name, image: image, zoom: state.zoom, offset: offset,
                selection: area == nil ? selection.keptSelection : nil)
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
            // An image file first shows fitted.
            if let zoom = new.zoom { zoomPan.restore(zoom: zoom, offset: new.offset) } else { zoomPan.fitWhenShown() }
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

    /// The purple border and "Capture 2 of 4 · 14:20:05 · Esc for live" while a capture shows, or
    /// "photo.png · Esc for live" for an image file; the frozen indicator of the live view waits
    /// under it.
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
