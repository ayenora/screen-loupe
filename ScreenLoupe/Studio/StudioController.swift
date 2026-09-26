import AppKit
import OSLog
import SwiftUI

/// The Screenshot studio (docs/product.md, Screenshot studio): its frame, its palette, Capture,
/// Copy and Save, and the frame's sizes and Aspect Lock. Shown and hidden on its own, apart from the Viewer and the Capture Area.
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
    private let sizePanel = StudioSizePanel()
    /// Built the first time Custom Size… is chosen, then kept.
    private var customSizesWindow: NSPanel?

    init(settings: SettingsStore, permissions: PermissionsManager, export: ExportController) {
        self.settings = settings
        self.permissions = permissions
        self.export = export
        frame = CaptureAreaController(settings: settings, kind: .studio) {
            StudioPlacement.defaultFrame(in: $0, paletteWidth: StudioPalette.width)
        }
        // A window picked with Aspect Lock on gives the lock its ratio, as a size does.
        frame.onPickWindow = { [weak self] in self?.frame.pickWindow { self?.retakeAspectRatio() } }
        palette.onCapture = { [weak self] in self?.capture() }
        palette.onCopy = { [weak self] in self?.copy() }
        palette.onSave = { [weak self] in self?.save() }
        palette.onSize = { [weak self] in self?.showSizes(beside: $0) }
        palette.onToggleAspectLock = { [weak self] in self?.toggleAspectLock() }
        palette.onToggleOnTop = { [weak self] in self?.toggleKeepOnTop() }
        palette.onHide = { [weak self] in self?.hide() }
        palette.onDragStarted = { [weak self] in self?.sizePanel.dismiss() }
        palette.onMoved = { [weak self] in
            guard let self else { return }
            settings.update { $0.studioPaletteOrigin = self.palette.frame.origin }
        }
        settings.observe(\.studioOnTop) { [weak self] in self?.palette.keepsOnTop = $0 }
        settings.observe(\.studioAspectLocked) { [weak self] in self?.palette.aspectLocked = $0 }
        settings.observe(\.activeStudioAspectRatio) { [weak self] in self?.frame.aspectRatio = $0.map { CGFloat($0) } }
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
        sizePanel.dismiss()
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

    // MARK: Sizes

    /// The frame's size in pixels of its display, for the checkmark in the size lists.
    var pixelSize: PixelSize? { frame.pixelSize }

    /// Gives the frame `size` pixels (`CaptureAreaController.resize(toPixels:)`), unless its display
    /// can't hold them. With Aspect Lock on, the lock takes the frame's ratio.
    func applySize(_ size: PixelSize) {
        guard isVisible else { return }
        if frame.resize(toPixels: size) { retakeAspectRatio() }
    }

    /// With Aspect Lock on, the lock keeps the frame's ratio from now on.
    private func retakeAspectRatio() {
        guard settings.settings.studioAspectLocked else { return }
        let ratio = frameRatio
        settings.update { $0.studioAspectRatio = ratio }
    }

    /// Turning Aspect Lock on takes the frame's current ratio.
    func toggleAspectLock() {
        let ratio = frameRatio
        settings.update {
            $0.studioAspectLocked.toggle()
            if $0.studioAspectLocked { $0.studioAspectRatio = ratio }
        }
    }

    /// Width over height, in pixels of the frame's display.
    private var frameRatio: Double {
        if let size = frame.pixelSize { return Double(size.width) / Double(size.height) }
        return Double(frame.captureRect.width / frame.captureRect.height)
    }

    /// The Size list beside the palette's Size button (`StudioSizePanel`), or closes it while it
    /// shows. Nothing is activated.
    private func showSizes(beside button: NSView) {
        if sizePanel.isVisible {
            sizePanel.dismiss()
            return
        }
        let list = StudioSizeList(
            current: frame.pixelSize, custom: settings.settings.studioCustomSizes,
            apply: { [weak self] size in
                self?.sizePanel.dismiss()
                self?.applySize(size)
            },
            editCustomSizes: { [weak self] in
                self?.sizePanel.dismiss()
                self?.showCustomSizes()
            })
        let paletteFrame = palette.frame
        let anchorTop = palette.convertToScreen(button.convert(button.bounds, to: nil)).maxY
        let visible = palette.screen?.visibleFrame ?? paletteFrame
        sizePanel.show(list, beside: palette) {
            StudioPlacement.popoverOrigin(size: $0, beside: paletteFrame, anchorTop: anchorTop, in: visible)
        }
    }

    /// The Custom Sizes window: four slots for sizes of the user's own. A non-activating panel, so
    /// opening it from the palette leaves the app the user works in active and brings no other
    /// window of this app forward; it becomes key for typing. At the normal level, so other apps'
    /// windows can cover it. Its content is made anew each time it opens: an edit not taken with
    /// Enter is dropped with it.
    func showCustomSizes() {
        let window = customSizesWindow ?? makeCustomSizesWindow()
        customSizesWindow = window
        if !window.isVisible {
            let host = NSHostingController(
                rootView: CustomSizesView(store: settings) { [weak window] in window?.performClose(nil) })
            host.sizingOptions = .preferredContentSize
            window.contentViewController = host
            window.center()
        }
        window.orderFrontRegardless()
        window.makeKey()
    }

    private func makeCustomSizesWindow() -> NSPanel {
        let window = NSPanel(
            contentRect: .zero, styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: true)
        window.title = "Custom Sizes"
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.level = .normal
        window.hidesOnDeactivate = true
        return window
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
        // A picture holds one display's pixels: a frame reaching onto another display, or off every
        // display, would give a smaller picture than the frame says.
        guard frame.isWhollyOnOneDisplay else {
            frame.showNotice("Frame is not wholly on one display")
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
