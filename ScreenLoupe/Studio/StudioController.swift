import AppKit
import OSLog

/// The Screenshot studio (docs/product.md, Screenshot studio): its frame, its palette, and Capture,
/// Copy and Save. Shown and hidden on its own, apart from the Viewer and the Capture Area.
///
/// The frame is a `CaptureAreaController` of kind `.studio`: the Capture Area's window, drawing,
/// dragging and snapping, without its locks. The palette is a separate panel, parked anywhere.
@MainActor
final class StudioController {
    /// Called when a capture needs Screen Recording access: the Viewer explains and asks for it.
    /// `deniedByCapture`: ScreenCaptureKit refused although the preflight check said yes.
    var onNeedsPermission: ((_ deniedByCapture: Bool) -> Void)?
    /// The numbers of the app's windows a picture keeps — the Viewer and the Capture Area frame;
    /// every other window of the app is left out.
    var capturedAppWindows: (() -> [Int])?

    private let frame: CaptureAreaController
    private let palette = StudioPalette()
    private let settings: SettingsStore
    private let permissions: PermissionsManager
    private let export: ExportController
    private let log = Logger(category: "studio")
    /// A capture is on its way; presses meanwhile are ignored.
    private var isCapturing = false
    /// The last save panel; while it is open, the commands bring it forward instead.
    private var savePanel: NSSavePanel?

    init(settings: SettingsStore, permissions: PermissionsManager, export: ExportController) {
        self.settings = settings
        self.permissions = permissions
        self.export = export
        frame = CaptureAreaController(settings: settings, kind: .studio) {
            StudioPlacement.defaultFrame(in: $0, paletteWidth: StudioPalette.width)
        }
        frame.onPickWindow = { [weak self] in self?.frame.pickWindow {} }
        palette.onCapture = { [weak self] in self?.capture() }
        palette.onCopy = { [weak self] in self?.copy() }
        palette.onSave = { [weak self] in self?.save() }
        palette.onToggleOnTop = { [weak self] in self?.toggleKeepOnTop() }
        palette.onHide = { [weak self] in self?.hide() }
        palette.onMoved = { [weak self] in
            guard let self else { return }
            settings.update { $0.studioPaletteOrigin = self.palette.frame.origin }
        }
        settings.observe(\.studioOnTop) { [weak self] in self?.palette.keepsOnTop = $0 }
    }

    // MARK: Visibility

    var isVisible: Bool { frame.isVisible }

    /// Shows the frame where it was, or centred on the main display the first time, and the palette
    /// where it was, or beside the frame.
    func show() {
        frame.show()
        if !palette.isVisible { placePalette() }
        palette.orderFrontRegardless()
    }

    func hide() {
        frame.hide()
        palette.orderOut(nil)
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    var keepsOnTop: Bool { settings.settings.studioOnTop }

    func toggleKeepOnTop() {
        settings.update { $0.studioOnTop.toggle() }
    }

    // MARK: Displays

    /// Keeps the frame and the palette on a connected display.
    func screenParametersChanged() {
        frame.screenParametersChanged()
        if palette.isVisible, converter?.owningDisplay(for: GlobalRect(rect: palette.frame)) == nil {
            placePalette(besideFrame: true)
        }
    }

    private var converter: DisplayCoordinateConverter? {
        DisplayLayout.current().map(DisplayCoordinateConverter.init(layout:))
    }

    /// Where the palette was left, when that is still on a display; else beside the frame.
    private func placePalette(besideFrame: Bool = false) {
        guard let converter else { return }
        let size = palette.frame.size
        if !besideFrame, let saved = settings.settings.studioPaletteOrigin,
            converter.owningDisplay(for: GlobalRect(rect: CGRect(origin: saved, size: size))) != nil
        {
            palette.setFrameOrigin(saved)
            return
        }
        let area = frame.captureRect
        let display = converter.owningDisplay(for: GlobalRect(rect: area))
        let visible =
            display.flatMap { NSScreen.screen(forDisplay: $0.id) }?.visibleFrame ?? NSScreen.main?.visibleFrame ?? area
        palette.setFrameOrigin(StudioPlacement.paletteOrigin(size: size, beside: area, in: visible))
    }

    // MARK: Capture, Copy, Save

    /// Copies the frame's pixels to the clipboard, then asks where to save them.
    func capture() {
        take { [weak self] image in
            guard let png = ScreenshotExporter.pngData(image) else { return NSSound.beep() }
            self?.copy(image, png: png)
            self?.save(png)
        }
    }

    func copy() {
        take { [weak self] in self?.copy($0) }
    }

    func save() {
        take { [weak self] image in
            guard let png = ScreenshotExporter.pngData(image) else { return NSSound.beep() }
            self?.save(png)
        }
    }

    private func copy(_ image: CGImage, png: Data? = nil) {
        guard ScreenshotExporter.copy(image, png: png) else { return NSSound.beep() }
        frame.showNotice("Copied \(image.width) × \(image.height) px")
    }

    /// The sandbox lets the app write only where the user picks, so saving goes through the save
    /// panel, opened in the screenshot folder with the file already named.
    private func save(_ png: Data) {
        NSApp.activate()
        savePanel = export.savePNG(png, kind: "Screenshot", sheetOn: nil) { [weak self] url in
            self?.frame.showNotice("Saved \(url.lastPathComponent)")
        }
    }

    /// Captures the frame's rect and hands the image on, unless the studio was hidden meanwhile.
    /// While a save panel is open, brings it forward instead: one panel at a time, and none in the
    /// picture.
    private func take(_ then: @escaping (CGImage) -> Void) {
        guard isVisible, !isCapturing else { return }
        if let savePanel, savePanel.isVisible {
            NSApp.activate()
            savePanel.makeKeyAndOrderFront(nil)
            return
        }
        guard permissions.hasScreenRecordingAccess else {
            onNeedsPermission?(false)
            return
        }
        guard let geometry = frame.captureGeometry else { return NSSound.beep() }
        isCapturing = true
        let included = capturedAppWindows?() ?? []
        Task {
            defer { isCapturing = false }
            do {
                let image = try await StudioCapture.image(of: geometry, including: included)
                if isVisible { then(image) }
            } catch  where ScreenCaptureManager.isPermissionError(error) {
                onNeedsPermission?(true)
            } catch {
                log.error("Studio capture failed: \(error.localizedDescription, privacy: .public)")
                NSSound.beep()
                frame.showNotice("Capture failed")
            }
        }
    }
}
