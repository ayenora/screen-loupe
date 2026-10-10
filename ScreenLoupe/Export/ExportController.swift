import AppKit
import UniformTypeIdentifiers

/// Copy and Save, of the view and of the source: the images, the
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
    var canExport: Bool { viewer.showsCapture && frameStore.shownFrame != nil }

    /// Copies what the Viewer shows (`viewImage`); returns the image copied, or `nil` after a beep
    /// when there was nothing to copy.
    @discardableResult
    func copyView() -> CGImage? {
        let what = viewer.hasSelection ? "Selection" : "View"
        guard let image = viewImage(), ScreenshotExporter.copy(image) else {
            NSSound.beep()
            return nil
        }
        viewer.showToast("\(what) copied")
        return image
    }

    /// Copies the source at its native pixels (`sourceImage`); returns the image copied, or `nil`
    /// after a beep when there was nothing to copy.
    @discardableResult
    func copySource() -> CGImage? {
        guard let image = sourceImage(), ScreenshotExporter.copy(image) else {
            NSSound.beep()
            return nil
        }
        viewer.showToast("Source copied")
        return image
    }

    func saveView() {
        save(viewImage(), kind: "View")
    }

    func saveSource() {
        save(sourceImage(), kind: "Source")
    }

    /// What the Viewer shows, or just the Select tool's selection while there is one, with the grid
    /// only when Settings › Screenshots includes it.
    private func viewImage() -> CGImage? {
        guard canExport else { return nil }
        return viewer.renderViewImage(showsGrid: settings.settings.gridInCopyView)
    }

    private func sourceImage() -> CGImage? {
        guard canExport, let frame = frameStore.shownFrame else { return nil }
        return ScreenshotExporter.sourceImage(from: frame, colorSpace: frame.colorSpace)
    }

    /// The image is taken when the command is given, before the save panel opens. `kind` names the
    /// file: "View" or "Source" (`ScreenshotName`).
    private func save(_ image: CGImage?, kind: String) {
        guard let image, let png = ScreenshotExporter.pngData(image), let window = viewer.window else {
            return NSSound.beep()
        }
        let name = ScreenshotName.fileName(kind: kind, style: settings.settings.fileNameStyle)
        saveImage(png, type: .png, name: name, sheetOn: window) { [weak self] url in
            self?.viewer.showToast("Saved \(url.lastPathComponent)")
        }
    }

    /// The save panel for `data` of `type`, suggesting `name` (`ScreenshotName`), in the folder used
    /// last: a sheet on `window`, or a panel of its own without one (the Screenshot studio).
    /// `onSaved` runs once the file is written. Returns the panel, open until the user saves or
    /// cancels.
    @discardableResult
    func saveImage(
        _ data: Data, type: UTType, name: String, sheetOn window: NSWindow?, onSaved: @escaping (URL) -> Void
    ) -> NSSavePanel {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = name
        panel.directoryURL =
            settings.settings.screenshotDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url, options: .atomic)
                self?.settings.update { $0.screenshotDirectory = url.deletingLastPathComponent().path }
                onSaved(url)
                if self?.settings.settings.revealsSavedFile == true {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            } catch {
                if let window {
                    NSAlert(error: error).beginSheetModal(for: window)
                } else {
                    NSAlert(error: error).runModal()
                }
            }
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
        return panel
    }
}
