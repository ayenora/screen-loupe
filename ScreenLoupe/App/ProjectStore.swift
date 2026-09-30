import AppKit
import ImageIO
import OSLog
import Observation
import UniformTypeIdentifiers

/// The working project: the reference layers, with copies of their
/// images, and the ruler. There is one, saved as you work and restored at launch.
///
/// It lives in Application Support: `project.json` and the images beside it, so a reference keeps
/// working when its original file moves or goes away.
@MainActor
@Observable
final class ProjectStore {
    struct Project: Codable, Equatable {
        var references = ReferenceStack()
        var ruler: CornerRuler?

        init() {}

        /// A key that is missing or unreadable keeps its default; the rest loads as saved.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = Project()
            references = c.value(.references, or: d.references)
            ruler = c.value(.ruler, or: d.ruler)
        }
    }

    private(set) var project: Project
    @ObservationIgnored let folder: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(category: "project")

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        folder = support.appending(path: Bundle.main.bundleIdentifier ?? "Screen Loupe").appending(path: "Project")
        let file = folder.appending(path: Self.projectFile)
        let data = try? Data(contentsOf: file)
        let saved = data.flatMap { try? JSONDecoder().decode(Project.self, from: $0) }
        project = saved ?? Project()
        // A layer whose image is gone can't be shown.
        let missing = project.references.layers.filter {
            !FileManager.default.fileExists(atPath: imageURL(for: $0.fileName).path)
        }
        for layer in missing { project.references.remove(layer.id) }
        // Images no layer uses are removed; not when the project couldn't be read, whose images they
        // may be — also when the file is there but reading it failed.
        if saved != nil || !FileManager.default.fileExists(atPath: file.path) {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            let stray = ReferenceStack.strayFiles(
                files, layers: project.references.layers, projectFile: Self.projectFile)
            for name in stray { deleteImage(name) }
        }
    }

    private static let projectFile = "project.json"

    func update(_ change: (inout Project) -> Void) {
        var next = project
        change(&next)
        guard next != project else { return }
        project = next
        scheduleSave()
    }

    func imageURL(for fileName: String) -> URL {
        folder.appending(path: fileName)
    }

    /// Copies an image into the project and returns a layer for it, or `nil` when it isn't an image.
    func importImage(at url: URL) -> ReferenceLayer? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return importImage(source, name: url.lastPathComponent, fileExtension: url.pathExtension) {
            try FileManager.default.copyItem(at: url, to: $0)
        }
    }

    /// Writes pasted image data of `type` (a uniform type identifier) into the project and returns
    /// a layer for it, or `nil` when it isn't an image.
    func importImage(data: Data, type: String, name: String) -> ReferenceLayer? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return importImage(
            source, name: name, fileExtension: UTType(type)?.preferredFilenameExtension ?? "",
            write: { try data.write(to: $0) })
    }

    /// Puts the image `source` reads into the project with `write` and returns a layer named `name`.
    private func importImage(
        _ source: CGImageSource, name: String, fileExtension: String, write: (URL) throws -> Void
    ) -> ReferenceLayer? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        let id = UUID()
        let fileName = "\(id.uuidString).\(fileExtension.isEmpty ? "png" : fileExtension.lowercased())"
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try write(imageURL(for: fileName))
        } catch {
            log.error("Importing a reference failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        // A larger image shows only its top-left part (`ReferencesController.image(for:)`).
        // A photo taken turned shows upright (`ImageFileLoader.image(at:)`), its sides swapped.
        let orientation = ImageOrientation(exif: properties[kCGImagePropertyOrientation] as? Int ?? 1)
        let upright = orientation.swapsSides ? (width: height, height: width) : (width: width, height: height)
        let kept = ImageBudget.fitted(width: upright.width, height: upright.height)
        return ReferenceLayer(
            id: id, name: name, fileName: fileName,
            imageSize: CGSize(width: kept.width, height: kept.height))
    }

    /// Writes `frame`'s pixels, a recent capture's or the frozen frame's, into the project as a TIFF
    /// in their colour space (`CaptureReference.tiffData`), off the main thread, and returns a layer
    /// for them as `source` places it (`CaptureReference.layer`), or `nil` when that fails.
    func importPixels(of frame: ViewerFrame, as source: CaptureReference.Source) async -> ReferenceLayer? {
        let id = UUID()
        let fileName = "\(id.uuidString).tiff"
        let isWritten = await Self.writeTIFF(
            of: frame, space: UncheckedSendable(value: frame.colorSpace), to: imageURL(for: fileName), in: folder)
        guard isWritten else {
            log.error("Importing a capture as a reference failed")
            return nil
        }
        return CaptureReference.layer(
            source, layout: frame.layout, pictureOrigin: frame.areaOrigin, id: id, fileName: fileName,
            timeZone: .current)
    }

    @concurrent
    private nonisolated static func writeTIFF(
        of frame: ViewerFrame, space: UncheckedSendable<CGColorSpace>, to url: URL, in folder: URL
    ) async -> Bool {
        let buffer = frame.pixelBuffer
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer),
            let data = CaptureReference.tiffData(
                bgra: base, width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer),
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: space.value, hasAlpha: frame.hasAlpha)
        else { return false }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Removes an image the project no longer uses.
    func deleteImage(_ fileName: String) {
        try? FileManager.default.removeItem(at: imageURL(for: fileName))
    }

    /// Saves now instead of after the short delay, before the app quits.
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        write()
    }

    /// Dragging a layer changes the project many times a second; one write after it settles is enough.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.write()
        }
    }

    private func write() {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(project)
            try data.write(to: folder.appending(path: Self.projectFile), options: .atomic)
        } catch {
            log.error("Saving the project failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
