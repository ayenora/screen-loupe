import AppKit
import SwiftUI

/// The Viewer's content while it shows the capture: the magnified image with the overlay, the
/// frozen indicator, the status panel and the toast over it, and the side column (Color Meter,
/// References or Recent Captures) at its right. Image files dropped on it, and images pasted into
/// it, become reference layers or recent captures (`ImagePlacement`). What happens inside it is
/// wired here; the window controller only places it.
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
        // Each frame of a zoom glide as well as each change of the model.
        zoomPan.observePresented { [weak self] in
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
        captures.onTakeSnapshot = { [weak self] in self?.takeSnapshot() }
        inspector.onChange = { [weak self] in
            self?.overlay.needsDisplay = true
            self?.meterPanel.refresh()
        }
        references.onChange = { [weak self] in
            self?.viewerView.requestDraw()
            self?.overlay.needsDisplay = true
        }
        references.onPaste = { [weak self] in self?.paste(as: .references) }
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
        showToast("Region copied")
    }

    // MARK: Dropped and pasted images

    /// Where a dropped or pasted image goes: `chosen`
    /// by Paste as Reference or Paste for Inspection, else by the open panel.
    private func placement(chosen: ImageDestination?) -> ImagePlacement {
        ImagePlacement.of(
            chosen: chosen, showsReferences: sidePanelLayout?.showsReferences == true,
            showsCaptures: sidePanelLayout?.showsCaptures == true)
    }

    /// Whether the references take another layer: Edit › Paste as Reference is off when they don't.
    var canAddReference: Bool { references.stack.canAdd }

    /// Whether a drag is over the content and would be taken; its border shows then.
    private var isDropTargeted = false {
        didSet { needsDisplay = true }
    }
    /// Counts image files asked for, by Open Image, a drop or a paste, so only the latest request shows;
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
        ImageInput.imageFileURLs(on: info.draggingPasteboard)
    }

    /// Text, web links and other files are refused, and so are references with the stack full.
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isDropTargeted =
            !imageURLs(sender).isEmpty
            && (placement(chosen: nil) != .place(.references) || references.stack.canAdd)
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
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            place(.files(urls), placement(chosen: nil), askingAt: point)
        }
        return true
    }

    /// Edit › Paste in the Viewer, the References panel's Paste (`chosen` `.references`), and Edit ›
    /// Paste as Reference or Paste for Inspection: the clipboard's image goes where a drop would,
    /// or where `chosen` says. The menu that asks comes up at the pointer over the image, else at
    /// its centre. Nothing to paste, or a full stack of references, beeps and changes nothing.
    func paste(as chosen: ImageDestination?) {
        guard let input = ImageInput.fromClipboard() else { return NSSound.beep() }
        let placement = placement(chosen: chosen)
        if placement == .place(.references), !references.stack.canAdd { return NSSound.beep() }
        let pointer = window.map { convert($0.mouseLocationOutsideOfEventStream, from: nil) }
        place(input, placement, askingAt: ImagePlacement.menuPoint(pointer: pointer, imageArea: imageArea.frame))
    }

    private func place(_ input: ImageInput, _ placement: ImagePlacement, askingAt point: CGPoint) {
        switch placement {
        case .place(.references):
            addReferences(input)
        case .place(.captures):
            inspect(input)
        case .ask:
            let menu = NSMenu()
            menu.autoenablesItems = false
            let add = menu.addItem(
                withTitle: "Add as Reference", action: #selector(placeAsChosen(_:)), keyEquivalent: "")
            add.isEnabled = references.stack.canAdd
            menu.addItem(withTitle: "Open for Inspection", action: #selector(placeAsChosen(_:)), keyEquivalent: "")
                .tag = 1
            for item in menu.items {
                item.target = self
                item.representedObject = input
            }
            menu.popUp(positioning: nil, at: point, in: self)
        }
    }

    @objc private func placeAsChosen(_ item: NSMenuItem) {
        guard let input = item.representedObject as? ImageInput else { return }
        if item.tag == 0 {
            addReferences(input)
        } else {
            inspect(input)
        }
    }

    /// Adds image files or a pasted image as reference layers, as Add… does, and opens the
    /// References panel on them as its toolbar button does. When none could be added, says so.
    private func addReferences(_ input: ImageInput) {
        let count = references.stack.layers.count
        let failed: [String]
        switch input {
        case .files(let urls):
            failed = references.add(urls).map(\.lastPathComponent)
        case .data(let data, let type):
            let name = ImageInput.pastedName
            let added = references.add(data, type: type, name: name)
            failed = added || !references.stack.canAdd ? [] : [name]
        }
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

    /// Decodes image files, or a pasted image, off the main thread and keeps each as a recent
    /// capture, in order, the last one shown, as Open Image does; only as many as the list keeps.
    /// The rows are added once all are read, so the Viewer shows the last one only, not each in
    /// turn. When none could be read, says so.
    private func inspect(_ input: ImageInput) {
        let files: [URL]
        switch input {
        case .files(let urls):
            files = urls
        case .data(let data, _):
            return inspectPasted(data)
        }
        let urls = Array(files.suffix(RecentCaptures.limit))
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
            guard let last = read.last else { return showFailure(failed.map(\.lastPathComponent), verb: "opened") }
            read.dropLast().forEach(captures.add)
            showFile(last)
        }
    }

    /// A pasted image as a recent capture, shown, named "Pasted image".
    private func inspectPasted(_ data: Data) {
        let request = newImageRequest()
        Task {
            let decoded = await ImageFileLoader.frame(data: data)
            guard request == imageRequest else { return }
            let name = ImageInput.pastedName
            guard let decoded else { return showFailure([name], verb: "opened") }
            showFile(RecentCaptures.file(decoded.frame, thumbnail: decoded.thumbnail, name: name))
        }
    }

    /// "The image couldn't be added." or "…opened.", naming the files.
    private func showFailure(_ names: [String], verb: String) {
        let alert = NSAlert()
        alert.messageText = names.count == 1 ? "The image couldn't be \(verb)." : "The images couldn't be \(verb)."
        alert.informativeText = names.joined(separator: ", ")
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

    /// Keeps an image file as the newest recent capture and shows it in place of the live view, fitted to the Viewer
    /// (`show`), with Recent Captures open.
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

    /// The size of the frame Take Snapshot takes (`FrameStore.snapshotFrame`), or `nil` without one.
    /// Access to capture is the window controller's to check.
    var snapshotFrameSize: PixelSize? { frameStore.snapshotFrame?.layout.size }

    /// Take Snapshot: keeps what the live view shows of the Capture
    /// Area's frame — its selection, or else the part in the Viewer — as the newest recent capture,
    /// whatever the Viewer shows, without showing it (`RecentCaptureRules.snapshotArea`). It opens as
    /// the live view was when it was taken: at its zoom, with the kept pixels where they were, and
    /// without a selection. With nothing to keep it beeps.
    func takeSnapshot() {
        guard let frame = frameStore.snapshotFrame else { return NSSound.beep() }
        let current = (zoom: zoomPan.state.zoom, offset: zoomPan.state.offset, selection: selection.keptSelection)
        let view = RecentCaptureRules.snapshotView(savedLive: liveView, current: current)
        let size = frame.layout.size
        let live = ZoomPanState(
            zoom: view.zoom, offset: view.offset, contentSize: CGSize(width: size.width, height: size.height),
            viewportSize: zoomPan.state.viewportSize)
        guard let area = RecentCaptureRules.snapshotArea(selection: view.selection, in: live),
            let capture = RecentCaptures.snapshot(
                of: frame, area: area, zoom: view.zoom,
                offset: RecentCaptureRules.snapshotOffset(view.offset, zoom: view.zoom, area: area))
        else { return NSSound.beep() }
        captures.add(capture)
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

    /// The purple border and "Capture 2 of 8 · 14:20:05 · Esc for live" while a capture shows, or
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
