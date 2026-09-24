import AppKit
import ImageIO
import OSLog
import Observation

/// The working project (docs/product.md, Project): the reference layers, with copies of their
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
        let file = folder.appending(path: "project.json")
        if let data = try? Data(contentsOf: file), let project = try? JSONDecoder().decode(Project.self, from: data) {
            self.project = project
        } else {
            project = Project()
        }
        // A layer whose image is gone can't be shown.
        let missing = project.references.layers.filter {
            !FileManager.default.fileExists(atPath: imageURL(for: $0.fileName).path)
        }
        for layer in missing { project.references.remove(layer.id) }
    }

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
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        let id = UUID()
        let fileName = "\(id.uuidString).\(url.pathExtension.isEmpty ? "png" : url.pathExtension.lowercased())"
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: imageURL(for: fileName))
        } catch {
            log.error("Importing a reference failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        return ReferenceLayer(
            id: id, name: url.lastPathComponent, fileName: fileName,
            imageSize: CGSize(width: width, height: height))
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
            try data.write(to: folder.appending(path: "project.json"), options: .atomic)
        } catch {
            log.error("Saving the project failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
