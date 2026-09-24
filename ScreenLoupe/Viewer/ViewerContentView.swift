import AppKit
import SwiftUI

/// The Viewer's content while it shows the capture: the magnified image with the overlay, the
/// frozen indicator, the status panel and the toast over it, and the side column (Color Meter,
/// References) at its right. What happens inside it is wired here; the window controller only
/// places it.
@MainActor
final class ViewerContentView: NSStackView {
    let viewerView: ViewerView
    let statusView = CaptureStatusView()
    let ruler: RulerController

    private let inspector: PixelInspector
    private let overlay: ViewerOverlayView
    private let meterPanel: ColorMeterPanel
    private let references: ReferencesController
    private let sidePanels: SidePanelStack
    private let toast = ToastView()
    private let frozenIndicator = FrozenIndicatorView()
    /// The magnified image with everything drawn over it; left of the side column.
    private let imageArea = NSView()

    init(
        settings: SettingsStore, frameStore: FrameStore, zoomPan: ZoomPanController, inspector: PixelInspector,
        project: ProjectStore
    ) {
        self.inspector = inspector
        let viewerView = ViewerView(frameStore: frameStore, zoomPan: zoomPan, inspector: inspector)
        self.viewerView = viewerView
        overlay = ViewerOverlayView(zoomPan: zoomPan, inspector: inspector)
        overlay.drawableScale = { [weak viewerView] in viewerView?.drawableScale ?? 1 }
        overlay.sourceScale = { frameStore.latestFrame?.geometry.display.scale ?? 1 }
        meterPanel = ColorMeterPanel(inspector: inspector)
        ruler = RulerController(zoomPan: zoomPan, project: project)
        references = ReferencesController(project: project, zoomPan: zoomPan)
        viewerView.ruler = ruler
        overlay.ruler = ruler
        viewerView.references = references
        overlay.references = references
        let referencesPanel = NSHostingView(rootView: ReferencesPanel(references: references))
        // The side panel column sizes it, not its content.
        referencesPanel.sizingOptions = []
        sidePanels = SidePanelStack(meter: meterPanel, references: referencesPanel)
        super.init(frame: .zero)
        build()
        wire(zoomPan: zoomPan, settings: settings)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func build() {
        // Views don't clip by default since macOS 14; the reference frame and the ruler would draw
        // over the side panels.
        imageArea.clipsToBounds = true
        frozenIndicator.isHidden = true
        for view in [viewerView, overlay, frozenIndicator] as [NSView] {
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

    private func wire(zoomPan: ZoomPanController, settings: SettingsStore) {
        zoomPan.observe { [weak self] in
            guard let self else { return }
            viewerView.requestDraw()
            overlay.needsDisplay = true
            ruler.viewportChanged()
        }
        ruler.observe { [weak self] in self?.overlay.needsDisplay = true }
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

        sidePanels.onExpand = { panel in settings.update { $0.expandedSidePanel = panel } }
        sidePanels.onScale = { [weak references] scale in references?.scale = scale }
        sidePanels.width = CGFloat(settings.settings.sidePanelWidth)
        sidePanels.onResize = { width in settings.update { $0.sidePanelWidth = Double(width) } }

        // Settings › Viewer and the toolbar's toggles.
        settings.observe(\.viewerStyle) { [weak self] in self?.viewerView.style = $0 }
        settings.observe(\.wheelZoomNeedsCommand) { [weak self] in self?.viewerView.wheelZoomNeedsCommand = $0 }
        settings.observe(\.crosshairEnabled) { [weak self] in self?.overlay.showsCrosshair = $0 }
        settings.observe(\.crosshairColor) { [weak self] in self?.overlay.color = $0.nsColor }
        settings.observe(\.sidePanelLayout) { [weak self] layout in
            guard let self else { return }
            sidePanels.show(layout)
            references.isActive = layout.showsReferences
            // The eyedropper works only while the Color Meter is expanded, and then it comes first.
            viewerView.isPicking = layout.isMeterExpanded
            references.takesMouse = !layout.isMeterExpanded
        }
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

    func setFrozen(_ frozen: Bool) {
        frozenIndicator.isHidden = !frozen
        if !frozen { viewerView.forgetAreaOrigin() }
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
