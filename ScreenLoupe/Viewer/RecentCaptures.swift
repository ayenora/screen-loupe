import AppKit
import Observation

/// A picture kept by Take Snapshot, or an image file opened to inspect (docs/product.md, Recent
/// Captures). A snapshot keeps the part of the Capture Area's frame the Viewer shows, or the
/// selection, at native resolution, so every tool works on real screen pixels when it is opened again.
struct RecentCapture: Identifiable {
    let id = UUID()
    /// The frame, in a buffer of its own, cut to what was kept and to `ImageBudget`.
    let frame: ViewerFrame
    /// "Snapshot", or an image file's name.
    let name: String
    let date: Date
    /// The kept frame, or an image file, small, for the panel.
    let thumbnail: CGImage?
    /// An image file (docs/product.md, Open Image), not a snapshot of the screen.
    let isFile: Bool
    /// How the Viewer shows it: as when it was taken, then as it was last left. `nil`: fitted to the
    /// Viewer, as an image file first shows.
    var zoom: CGFloat?
    var offset: CGPoint
    var selection: CGRect?

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
}

/// The last snapshots of the Capture Area and images opened from files, kept in memory until the
/// app quits, and which of them the Viewer shows in place of the live view (docs/product.md, Recent
/// Captures).
@MainActor
@Observable
final class RecentCaptures {
    static let limit = RecentCaptureRules.limit
    /// A thumbnail's box in pixels: 2× the panel's largest square thumbnail, 50 pt at the widest
    /// column's scale (320 / 250), 64 pt.
    nonisolated private static let thumbnailBox = CGSize(width: 128, height: 128)

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

    /// Called with the capture shown before and the one shown now (`nil`: the live view).
    @ObservationIgnored var onShow: ((_ old: RecentCapture?, _ new: RecentCapture?) -> Void)?

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
        guard let kept = frame.copiedForKeeping(area: area) else { return nil }
        let keptImage = ScreenshotExporter.sourceImage(from: kept, colorSpace: kept.colorSpace)
        return RecentCapture(
            frame: kept, name: "Snapshot", date: Date(), thumbnail: keptImage.flatMap(thumbnail(of:)), isFile: false,
            zoom: zoom, offset: offset, selection: nil)
    }

    /// A row for the image file `name`, decoded into `frame` with its `thumbnail`
    /// (`ImageFileLoader.frame(at:)`): its buffer is already its own.
    static func file(_ frame: ViewerFrame, thumbnail: CGImage?, name: String) -> RecentCapture {
        RecentCapture(
            frame: frame, name: name, date: Date(), thumbnail: thumbnail, isFile: true,
            zoom: nil, offset: .zero, selection: nil)
    }

    /// Keeps `capture` as the newest; the oldest other than the shown one goes past the limit
    /// (`RecentCaptureRules.adding`).
    func add(_ capture: RecentCapture) {
        captures = RecentCaptureRules.adding(capture, to: captures) { $0.id == shownID }
        onChange?()
    }

    /// Shows a capture in the Viewer, or the live view for `nil`.
    func show(_ id: UUID?) {
        guard id != shownID else { return }
        let old = shown
        shownID = id
        onShow?(old, shown)
    }

    func remove(_ id: UUID) {
        if id == shownID { show(nil) }
        captures.removeAll { $0.id == id }
        onChange?()
    }

    /// Keeps how a capture was left, for the next time it shows.
    func keep(_ id: UUID, zoom: CGFloat, offset: CGPoint, selection: CGRect?) {
        guard let index = captures.firstIndex(where: { $0.id == id }) else { return }
        captures[index].zoom = zoom
        captures[index].offset = offset
        captures[index].selection = selection
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
