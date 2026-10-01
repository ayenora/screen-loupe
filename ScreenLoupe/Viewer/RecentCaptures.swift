import AppKit
import Observation

/// A picture kept by Take Snapshot, or an image file opened to inspect. A snapshot keeps the part of the Capture Area's
/// frame the Viewer shows, or the
/// selection, at native resolution, so every tool works on real screen pixels when it is opened again.
struct RecentCapture: Identifiable {
    let id: UUID
    /// The frame, in a buffer of its own, cut to what was kept and to `ImageBudget`. Only its place
    /// in the Capture Area changes (`RecentCaptures.areaOriginMoved`).
    var frame: ViewerFrame
    /// "Snapshot", or an image file's name.
    let name: String
    let date: Date
    /// The kept frame, or an image file, small, for the panel.
    let thumbnail: CGImage?
    /// An image file, not a snapshot of the screen.
    let isFile: Bool
    /// How the Viewer shows it: as when it was taken, then as it was last left. `nil`: fitted to the
    /// Viewer, as an image file first shows.
    var zoom: CGFloat?
    var offset: CGPoint
    var selection: CGRect?
    /// Linked captures share one zoom and offset, not the selection (`RecentCaptureRules.Link`).
    var isLinked = false

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    /// The user's locale and time zone, following changes to the time zone while the app runs.
    private static let dateFormatter = RecentCaptureRules.dateFormatter(
        locale: .autoupdatingCurrent, timeZone: .autoupdatingCurrent)

    var time: String { Self.timeFormatter.string(from: date) }

    /// "294 × 239 px": the kept picture's own size.
    var sizeText: String { RecentCaptureRules.sizeText(frame.layout.size) }
    /// "7/12, 14:32:05": when it was kept, in the user's format.
    var dateText: String { Self.dateFormatter.string(from: date) }

    /// What it is as a reference (Use as Reference).
    var referenceSource: CaptureReference.Source {
        isFile ? .image(name: name) : .snapshot(date: date)
    }
}

/// The last snapshots of the Capture Area and images opened from files, and which of them the Viewer
/// shows in place of the live view. Kept on disk as they change (`RecentCaptureStore`), so the
/// Viewer opens on them again after quitting, a crash or a restart.
@MainActor
@Observable
final class RecentCaptures {
    static let limit = RecentCaptureRules.limit
    /// The side of a row's square thumbnail in the panel, in points at scale 1 (`RecentCapturesPanel`).
    nonisolated static let thumbnailSide: CGFloat = 50
    /// A thumbnail's box in pixels: the largest thumbnail the panel shows, at the widest column's
    /// scale, at 2×.
    nonisolated private static let thumbnailBox: CGSize = {
        let side = thumbnailSide * SidePanel.widthRange.upperBound / SidePanel.widthRange.lowerBound * 2
        return CGSize(width: side, height: side)
    }()

    /// Newest first.
    private(set) var captures: [RecentCapture] = []
    /// The capture the Viewer shows, or `nil` for the live view.
    private(set) var shownID: UUID?
    /// The panel's content scale, 1 at the side column's narrowest.
    var scale: CGFloat = 1
    /// The size of the frame the live view shows, while Take Snapshot can take it
    /// (`ViewerWindowController.refreshSnapshot`): the Live row's subtitle. `nil` without one.
    var liveSize: PixelSize?
    /// Whether Take Snapshot has a frame to take, for the panel's camera button.
    var canTakeSnapshot: Bool { liveSize != nil }
    /// Take Snapshot, from the panel's camera button.
    @ObservationIgnored var onTakeSnapshot: (() -> Void)?
    /// The panel's Paste button: the clipboard's image as a new row.
    @ObservationIgnored var onPaste: (() -> Void)?
    /// The panel's Add… button: File › Open Image….
    @ObservationIgnored var onOpenImage: (() -> Void)?
    /// Use as Reference, from a row's context menu.
    @ObservationIgnored var onUseAsReference: ((RecentCapture) -> Void)?
    /// Whether the references take another layer: Use as Reference is off when they don't. Read
    /// while the panel draws, so it follows the stack.
    @ObservationIgnored var canUseAsReference: (() -> Bool)?

    /// Called with the capture shown before (`nil`: the live view) as it is put away, to keep how it
    /// was left.
    @ObservationIgnored var onPutAway: ((_ old: RecentCapture?) -> Void)?
    /// Called with the capture shown now (`nil`: the live view), after the one before was put away:
    /// leaving a linked capture also writes the view of the next one.
    @ObservationIgnored var onShow: ((_ new: RecentCapture?) -> Void)?

    var shown: RecentCapture? { captures.first { $0.id == shownID } }

    /// "Capture 2 of 8 · 14:20:05 · Esc for live", or "photo.png · Esc for live" for an image file,
    /// over the Viewer while `capture` shows.
    func label(for capture: RecentCapture) -> String {
        if capture.isFile { return "\(capture.name) · Esc for live" }
        let number = (captures.firstIndex { $0.id == capture.id } ?? 0) + 1
        return "Capture \(number) of \(captures.count) · \(capture.time) · Esc for live"
    }

    /// Called after a capture is added or removed.
    @ObservationIgnored var onChange: (() -> Void)?

    /// A snapshot of `area` of `frame` (source pixels), copied now so it no longer depends on the
    /// stream, shown at `zoom` and `offset` with no selection when it is opened. The thumbnail is
    /// drawn from the kept pixels. `nil` when nothing of the frame is kept.
    static func snapshot(of frame: ViewerFrame, area: CGRect, zoom: CGFloat, offset: CGPoint) -> RecentCapture? {
        guard let kept = frame.copiedForKeeping(area: area, colorSpace: frame.colorSpace) else { return nil }
        let keptImage = ScreenshotExporter.sourceImage(from: kept, colorSpace: kept.colorSpace)
        return RecentCapture(
            id: UUID(), frame: kept, name: "Snapshot", date: Date(), thumbnail: keptImage.flatMap(thumbnail(of:)),
            isFile: false,
            zoom: zoom, offset: offset, selection: nil)
    }

    /// A row for the image file `name`, decoded into `frame` with its `thumbnail`
    /// (`ImageFileLoader.frame(at:)`): its buffer is already its own.
    static func file(_ frame: ViewerFrame, thumbnail: CGImage?, name: String) -> RecentCapture {
        RecentCapture(
            id: UUID(), frame: frame, name: name, date: Date(), thumbnail: thumbnail, isFile: true,
            zoom: nil, offset: .zero, selection: nil)
    }

    /// Keeps `capture` as the newest; the oldest other than the shown one goes past the limit
    /// (`RecentCaptureRules.adding`).
    func add(_ capture: RecentCapture) {
        let before = captures
        captures = RecentCaptureRules.adding(capture, to: captures) { $0.id == shownID }
        store.add(capture)
        for pushedOut in before where !captures.contains(where: { $0.id == pushedOut.id }) {
            store.delete(pushedOut.id)
        }
        onChange?()
    }

    /// Shows a capture in the Viewer, or the live view for `nil`.
    func show(_ id: UUID?) {
        guard id != shownID else { return }
        onPutAway?(shown)
        shownID = id
        onShow?(shown)
        store.saveSoon()
    }

    func remove(_ id: UUID) {
        if id == shownID { show(nil) }
        captures.removeAll { $0.id == id }
        store.delete(id)
        onChange?()
    }

    /// Keeps how a capture was left, for the next time it shows; its zoom and offset also for every
    /// capture linked with it (`RecentCaptureRules.leaving`).
    func keep(_ id: UUID, zoom: CGFloat, offset: CGPoint, selection: CGRect?) {
        guard let index = captures.firstIndex(where: { $0.id == id }) else { return }
        captures[index].selection = selection
        apply(RecentCaptureRules.leaving(id, at: .init(zoom: zoom, offset: offset), in: links))
    }

    /// The size of the linked captures' pictures, or `nil` when none is linked.
    var linkedSize: PixelSize? { captures.first(where: \.isLinked)?.frame.layout.size }

    /// Whether `capture` can be linked now, or unlinked (`RecentCaptureRules.canLink`).
    func canLink(_ capture: RecentCapture) -> Bool {
        RecentCaptureRules.canLink(capture.id, in: links)
    }

    /// The Viewer's zoom and offset now, for linking and unlinking while a capture shows.
    @ObservationIgnored var viewerView: (() -> RecentCaptureRules.CaptureView)?
    /// Called with the shown capture when linking it gave it the group's view, to show it so.
    @ObservationIgnored var onAdoptView: ((RecentCapture) -> Void)?

    /// Links or unlinks a capture (`RecentCaptureRules.linking`, `unlinking`). Does nothing to one
    /// that can't be linked.
    func setLinked(_ id: UUID, _ linked: Bool) {
        guard let viewer = viewerView?() else { return }
        guard linked else {
            apply(RecentCaptureRules.unlinking(id, shown: shownID, viewer: viewer, in: links))
            return store.saveSoon()
        }
        guard let linking = RecentCaptureRules.linking(id, shown: shownID, viewer: viewer, in: links) else { return }
        apply(linking.links)
        if linking.showsNewView, let shown { onAdoptView?(shown) }
        store.saveSoon()
    }

    /// The captures as linking sees them.
    private var links: [RecentCaptureRules.Link<UUID>] {
        captures.map {
            .init(
                id: $0.id, size: $0.frame.layout.size, isLinked: $0.isLinked,
                view: .init(zoom: $0.zoom, offset: $0.offset))
        }
    }

    /// Takes the links and views a linking rule gave back, for the same captures in the same order.
    private func apply(_ links: [RecentCaptureRules.Link<UUID>]) {
        for (index, link) in zip(captures.indices, links) where captures[index].id == link.id {
            captures[index].isLinked = link.isLinked
            captures[index].zoom = link.view.zoom
            captures[index].offset = link.view.offset
        }
    }

    // MARK: Kept on disk

    @ObservationIgnored private let store = RecentCaptureStore()

    /// The shown capture's zoom, offset and selection as the Viewer shows them now, kept as they
    /// change; `nil` while the Viewer isn't laid out, and the capture's own view stands.
    @ObservationIgnored var shownView: (() -> (view: RecentCaptureRules.CaptureView, selection: CGRect?)?)?

    init() {
        store.index = { [weak self] in self?.index }
    }

    /// The captures kept last time (`RecentCaptureStore.load`): the Viewer back on the one it
    /// showed at once, or on the live view; the others join the list as they are read.
    func restore() {
        let kept = store.load()
        if let shown = kept.shown {
            captures = [shown]
            onChange?()
            show(shown.id)
        }
        let order = kept.entries.map(\.id)
        store.readRest(kept.entries.filter { $0.id != kept.shown?.id }) { [weak self] capture in
            self?.restored(capture, order: order)
        }
    }

    /// A capture kept last time, read after the list came up, in its place among the kept ones
    /// (`RecentCaptureRules.restoring`); pushed out when the list has filled up since, as the oldest.
    /// A linked one joins the links as they are now (`RecentCaptureRules.joining`).
    private func restored(_ capture: RecentCapture, order: [UUID]) {
        guard captures.count < Self.limit else { return store.delete(capture.id) }
        var capture = capture
        let link = RecentCaptureRules.joining(
            .init(
                id: capture.id, size: capture.frame.layout.size, isLinked: capture.isLinked,
                view: .init(zoom: capture.zoom, offset: capture.offset)),
            into: links)
        capture.isLinked = link.isLinked
        capture.zoom = link.view.zoom
        capture.offset = link.view.offset
        captures = RecentCaptureRules.restoring(capture, into: captures, order: order, id: \.id)
        onChange?()
    }

    /// The Capture Area's top-left moved by `shift` pixels: every snapshot keeps its place on the
    /// screen's pixels, as the reference layers do (`RecentCaptureRules.areaOrigin`), also those
    /// still being read or unreadable (`RecentCaptureStore.areaOriginMoved`).
    func areaOriginMoved(by shift: CGPoint) {
        guard shift != .zero else { return }
        for index in captures.indices {
            captures[index].frame.areaOrigin = RecentCaptureRules.areaOrigin(
                captures[index].frame.areaOrigin, isFile: captures[index].isFile, followingShift: shift)
        }
        store.areaOriginMoved(by: shift)
        store.saveSoon()
    }

    /// The shown capture's view changed: kept after a short delay.
    func shownViewChanged() {
        if shownID != nil { store.saveSoon() }
    }

    /// Keeps the list as it is now, before the app quits, with the captures still being written,
    /// waiting for them a few seconds at most; going back to the live view after is not kept, so the
    /// Viewer opens on what it shows now.
    func saveBeforeQuit() async {
        await store.close(timeout: 5)
    }

    /// The captures as the index keeps them: the shown one, and every one linked with it, at the
    /// Viewer's view now (`RecentCaptureRules.leaving`), as putting it away would keep them.
    private var index: RecentCaptureArchive.Index {
        let now = shownID == nil ? nil : shownView?()
        var links = links
        if let shownID, let now { links = RecentCaptureRules.leaving(shownID, at: now.view, in: links) }
        let entries = zip(captures, links).map { capture, link in
            let selection = if let now, capture.id == shownID { now.selection } else { capture.selection }
            return capture.entry(view: link.view, selection: selection)
        }
        return RecentCaptureArchive.Index(entries: entries, shownID: shownID)
    }

    /// `image` scaled down to fit the thumbnail box; a small image stays as it is. Drawn in its RGB
    /// space (`CGColorSpace.rgbSpace(forImageIn:)`), keeping its transparency; also off the main
    /// actor, for an image file.
    nonisolated static func thumbnail(of image: CGImage) -> CGImage? {
        let fit = min(1, thumbnailBox.width / CGFloat(image.width), thumbnailBox.height / CGFloat(image.height))
        guard fit < 1 else { return image }
        let width = max(1, Int((CGFloat(image.width) * fit).rounded()))
        let height = max(1, Int((CGFloat(image.height) * fit).rounded()))
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace.rgbSpace(forImageIn: image.colorSpace),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // A thumbnail, not a magnification: smoothing is right here.
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
