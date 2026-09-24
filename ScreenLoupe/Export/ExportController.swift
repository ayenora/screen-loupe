import AppKit

/// Copy and Save, of the view and of the source (docs/product.md, Screenshots): the images, the
/// clipboard, the save panel with the Settings › Screenshots choices, and the confirmations.
@MainActor
final class ExportController {
    private let frameStore: FrameStore
    private let settings: SettingsStore
    private let viewer: ViewerWindowController

    init(frameStore: FrameStore, settings: SettingsStore, viewer: ViewerWindowController) {
        self.frameStore = frameStore
        self.settings = settings
        self.viewer = viewer
    }

    /// Whether there is a frame to copy or save.
    var canExport: Bool { viewer.showsCapture && frameStore.latestFrame != nil }

    func copyView() {
        guard let image = viewImage(), ScreenshotExporter.copy(image) else { return NSSound.beep() }
        viewer.showToast("View copied")
    }

    func copySource() {
        guard let image = sourceImage(), ScreenshotExporter.copy(image) else { return NSSound.beep() }
        viewer.showToast("Source copied")
    }

    func saveView() {
        save(viewImage(), kind: "View")
    }

    func saveSource() {
        save(sourceImage(), kind: "Source")
    }

    /// What the Viewer shows, with the grid only when Settings › Screenshots includes it.
    private func viewImage() -> CGImage? {
        guard canExport else { return nil }
        return viewer.renderViewImage(showsGrid: settings.settings.gridInCopyView)
    }

    private func sourceImage() -> CGImage? {
        guard canExport, let frame = frameStore.latestFrame else { return nil }
        return ScreenshotExporter.sourceImage(
            from: frame, colorSpace: NSScreen.colorSpace(forDisplay: frame.geometry.display.id))
    }

    /// The image is taken when the command is given, before the save panel opens.
    private func save(_ image: CGImage?, kind: String) {
        guard let image, let png = ScreenshotExporter.pngData(image), let window = viewer.window else {
            return NSSound.beep()
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = ScreenshotExporter.fileName(kind: kind, style: settings.settings.fileNameStyle)
        panel.directoryURL =
            settings.settings.screenshotDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try png.write(to: url, options: .atomic)
                self?.settings.update { $0.screenshotDirectory = url.deletingLastPathComponent().path }
                self?.viewer.showToast("Saved \(url.lastPathComponent)")
                if self?.settings.settings.revealsSavedFile == true {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            } catch {
                NSAlert(error: error).beginSheetModal(for: window)
            }
        }
    }
}
