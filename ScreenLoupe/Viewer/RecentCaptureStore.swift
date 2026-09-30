import AppKit
import OSLog

/// Recent Captures on disk, so they outlast quitting, a crash or a restart (`RecentCaptureArchive`).
/// It lives in Application Support: `index.json` and each capture's PNG beside it. A capture's PNG
/// is written before the index names it, and the index drops a capture before its PNG goes, so the
/// index never points at a missing file; quitting waits for the PNGs being written.
@MainActor
final class RecentCaptureStore {
    typealias Archive = RecentCaptureArchive

    let folder: URL
    /// What to write: the captures as they are now, newest first, and the one shown. Asked at each
    /// write, so the shown capture's view is the Viewer's latest.
    var index: (() -> Archive.Index?)?
    /// The captures whose PNG is on disk, only these go in the index, with the colour space their
    /// pixels are in (`ViewerFrame.imageColorSpace`).
    private var written: [UUID: Archive.SavedColorSpace?] = [:]
    /// Captures kept on disk but not in the list, newest first: still being read after launch, or
    /// whose PNG couldn't be read — kept, file and entry, to try again at the next launch, as the
    /// failure may pass. The index names them in their places among the kept ones, while there is
    /// room.
    private var unlisted: [Archive.Entry] = []
    /// The kept captures' ids at launch, newest first: where an unlisted one goes in the index.
    private var keptOrder: [UUID] = []
    /// The PNGs being written; the last save before the app quits waits for them.
    private var writes: [UUID: Task<Void, Never>] = [:]
    private var saveTask: Task<Void, Never>?
    /// After the last save before the app quits: going back to the live view then isn't kept.
    private var isClosed = false
    private let log = Logger(category: "captures")

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        folder = support.appending(path: Bundle.main.bundleIdentifier ?? "Screen Loupe")
            .appending(path: "Recent Captures")
    }

    private func url(for id: UUID) -> URL {
        folder.appending(path: Archive.fileName(for: id))
    }

    /// What was kept last time: every capture, newest first, and the one the Viewer showed, read
    /// now so it shows before any live frame — `nil` for the live view, or when its PNG can't be
    /// read. The others wait for `readRest`. A capture whose PNG is gone is dropped; an unreadable
    /// index keeps nothing. Files the index doesn't name are removed.
    func load() -> (shown: RecentCapture?, entries: [Archive.Entry]) {
        let data = try? Data(contentsOf: folder.appending(path: Archive.indexName))
        let index = data.flatMap { try? JSONDecoder().decode(Archive.Index.self, from: $0) } ?? Archive.Index()
        let entries = Archive.restorable(index.entries).filter {
            FileManager.default.fileExists(atPath: url(for: $0.id).path)
        }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for file in Archive.strayFiles(files, kept: entries) {
            try? FileManager.default.removeItem(at: folder.appending(path: file))
        }
        unlisted = entries
        keptOrder = entries.map(\.id)
        guard let shown = entries.first(where: { $0.id == index.shownID }), let read = Self.read(shown, in: folder)
        else { return (nil, entries) }
        return (list(shown, read), entries)
    }

    /// Reads `entries`' PNGs off the main thread, one at a time and newest first, so only one
    /// picture is decoded at once, and hands each to `restored` as it comes. One that can't be read
    /// stays on disk and in the index, out of the list; one pushed out meanwhile isn't read.
    func readRest(_ entries: [Archive.Entry], restored: @escaping (RecentCapture) -> Void) {
        let folder = folder
        Task {
            for entry in entries {
                guard !isClosed, isUnlisted(entry.id) else { continue }
                let read = await Self.readInBackground(entry, in: folder)
                guard !isClosed, isUnlisted(entry.id), let read else { continue }
                restored(list(entry, read))
            }
        }
    }

    private func isUnlisted(_ id: UUID) -> Bool {
        unlisted.contains { $0.id == id }
    }

    /// A capture read back goes into the list, as written.
    private func list(_ entry: Archive.Entry, _ read: ReadCapture) -> RecentCapture {
        unlisted.removeAll { $0.id == entry.id }
        written.updateValue(read.frame.imageColorSpace.flatMap(Archive.SavedColorSpace.init), forKey: entry.id)
        return Self.capture(entry, frame: read.frame, thumbnail: read.thumbnail.value)
    }

    /// Writes `capture`'s pixels off the main thread, then the index with it. A capture deleted
    /// meanwhile loses its file again.
    func add(_ capture: RecentCapture) {
        let frame = capture.frame
        let space = frame.colorSpace
        let saved = Archive.SavedColorSpace(space)
        let file = url(for: capture.id)
        let folder = folder
        let id = capture.id
        writes[id] = Task {
            defer { writes[id] = nil }
            let isWritten = await Self.writePixels(
                of: frame, space: UncheckedSendable(value: space), to: file, in: folder)
            guard isWritten else { return log.error("Keeping a recent capture failed") }
            written.updateValue(saved, forKey: id)
            guard current?.entries.contains(where: { $0.id == id }) == true else { return delete(id) }
            saveNow()
        }
    }

    /// Takes `id` out of the index, then its PNG off the disk.
    func delete(_ id: UUID) {
        guard !isClosed else { return }
        written.removeValue(forKey: id)
        saveNow()
        try? FileManager.default.removeItem(at: folder.appending(path: Archive.fileName(for: id)))
    }

    /// Writes the index after a short delay: a pan or a zoom changes the shown capture's view many
    /// times a second; one write after it settles is enough.
    func saveSoon() {
        guard !isClosed else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.write()
        }
    }

    /// Writes the index now, instead of after the delay.
    func saveNow() {
        guard !isClosed else { return }
        saveTask?.cancel()
        saveTask = nil
        write()
    }

    /// The last save before the app quits: waits for the PNGs being written, up to `timeout`, so a
    /// capture just taken is kept, then writes the index. Nothing after it is kept.
    func close(timeout: Double) async {
        let pending = Array(writes.values)
        if !pending.isEmpty {
            _ = try? await withTimeout(seconds: timeout) {
                for write in pending { await write.value }
            }
        }
        saveNow()
        isClosed = true
    }

    private var current: Archive.Index? { index?() ?? nil }

    /// Writes the list's captures whose PNG is on disk, and the unlisted ones in their places while
    /// there is room (`RecentCaptureArchive.indexEntries`); an unlisted one past it is pushed out, its
    /// PNG removed once the index no longer names it.
    private func write() {
        guard var index = current else { return }
        let listed = index.entries.compactMap { entry -> Archive.Entry? in
            guard let space = written[entry.id] else { return nil }
            var entry = entry
            entry.colorSpace = space
            return entry
        }
        let fitted = Archive.indexEntries(listed: listed, unlisted: unlisted, order: keptOrder)
        index.entries = fitted.entries
        if let shown = index.shownID, !index.entries.contains(where: { $0.id == shown }) { index.shownID = nil }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(index)
            try data.write(to: folder.appending(path: Archive.indexName), options: .atomic)
        } catch {
            return log.error("Saving recent captures failed: \(error.localizedDescription, privacy: .public)")
        }
        for entry in fitted.dropped {
            unlisted.removeAll { $0.id == entry.id }
            try? FileManager.default.removeItem(at: url(for: entry.id))
        }
    }

    // MARK: Pixels

    /// The PNG of `frame`'s buffer, every byte as it is, written whole or not at all.
    @concurrent
    private nonisolated static func writePixels(
        of frame: ViewerFrame, space: UncheckedSendable<CGColorSpace>, to url: URL, in folder: URL
    ) async -> Bool {
        let buffer = frame.pixelBuffer
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer),
            let data = Archive.pngData(
                bgra: base, width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer),
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: space.value)
        else { return false }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    @concurrent
    private nonisolated static func readInBackground(_ entry: Archive.Entry, in folder: URL) async -> ReadCapture? {
        read(entry, in: folder)
    }

    /// A kept capture's PNG read back into a buffer like the one it was kept in, with its layout and
    /// colour space, and its thumbnail drawn from the decoded image. `nil` when it can't be read.
    private nonisolated static func read(_ entry: Archive.Entry, in folder: URL) -> ReadCapture? {
        guard let data = try? Data(contentsOf: folder.appending(path: Archive.fileName(for: entry.id))),
            let image = Archive.image(png: data),
            let buffer = ViewerFrame.makeBuffer(width: image.width, height: image.height)
        else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        let copied = CVPixelBufferGetBaseAddress(buffer).map {
            Archive.copyPixels(of: image, into: $0, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        guard copied == true else { return nil }
        // The space kept in the index is the pixels' own; the PNG's tag may be a stand-in for it.
        let space = entry.colorSpace?.space ?? CGColorSpace.rgbSpace(forImageIn: image.colorSpace)
        let layout = Archive.layout(entry.layout, pixels: PixelSize(width: image.width, height: image.height))
        let frame = ViewerFrame(
            pixelBuffer: buffer, layout: layout, displayID: nil, imageColorSpace: space, hasAlpha: entry.isFile)
        let thumbnail = RecentCaptures.thumbnail(of: image.copy(colorSpace: space) ?? image)
        return ReadCapture(frame: frame, thumbnail: UncheckedSendable(value: thumbnail))
    }

    private static func capture(_ entry: Archive.Entry, frame: ViewerFrame, thumbnail: CGImage?) -> RecentCapture {
        RecentCapture(
            id: entry.id, frame: frame, name: entry.name, date: entry.date, thumbnail: thumbnail,
            isFile: entry.isFile, zoom: entry.zoom, offset: entry.offset, selection: entry.selection,
            isLinked: entry.isLinked)
    }

    private struct ReadCapture: Sendable {
        let frame: ViewerFrame
        let thumbnail: UncheckedSendable<CGImage?>
    }
}

extension RecentCapture {
    /// The capture as the index keeps it, shown at `view` with `selection`. Its colour space is the
    /// store's to add (`RecentCaptureStore.write`).
    func entry(view: RecentCaptureRules.CaptureView, selection: CGRect?) -> RecentCaptureArchive.Entry {
        RecentCaptureArchive.Entry(
            id: id, name: name, date: date, isFile: isFile, zoom: view.zoom, offset: view.offset,
            selection: selection, isLinked: isLinked, layout: frame.layout, colorSpace: nil)
    }
}
