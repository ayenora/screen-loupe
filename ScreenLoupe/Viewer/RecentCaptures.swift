import AppKit
import Observation

/// A picture kept by a copy or save on the Viewer (docs/product.md, Recent Captures). It keeps the
/// Capture Area's frame at native resolution, not the copied image, so every tool works on real
/// screen pixels when it is opened again.
struct RecentCapture: Identifiable {
    let id = UUID()
    /// The frame, in a buffer of its own, cut to `ImageBudget`.
    let frame: CapturedFrame
    /// What was copied or saved: "View · 800%", "Selection", "Region" or "Source".
    let kind: String
    /// The size of the copied or saved image.
    let imageSize: PixelSize
    let date: Date
    /// The copied or saved image, small, for the panel.
    let thumbnail: CGImage?
    /// How the Viewer shows it: as when it was taken, then as it was last left.
    var zoom: CGFloat
    var offset: CGPoint
    var selection: CGRect?

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var time: String { Self.timeFormatter.string(from: date) }
}

/// The last four pictures copied or saved on the Viewer, kept in memory until the app quits, and
/// which of them the Viewer shows in place of the live view (docs/product.md, Recent Captures).
@MainActor
@Observable
final class RecentCaptures {
    static let limit = 4
    /// The side of a thumbnail's box in pixels: 2× the panel's widest row thumbnail.
    private static let thumbnailBox = CGSize(width: 200, height: 132)

    /// Newest first.
    private(set) var captures: [RecentCapture] = []
    /// The capture the Viewer shows, or `nil` for the live view.
    private(set) var shownID: UUID?
    /// The panel's content scale, 1 at the side column's narrowest.
    var scale: CGFloat = 1

    /// Called with the capture shown before and the one shown now (`nil`: the live view).
    @ObservationIgnored var onShow: ((_ old: RecentCapture?, _ new: RecentCapture?) -> Void)?

    var shown: RecentCapture? { captures.first { $0.id == shownID } }

    /// "Capture 2 of 4 · 14:20:05 · Esc for live", over the Viewer while `capture` shows.
    func label(for capture: RecentCapture) -> String {
        let number = (captures.firstIndex { $0.id == capture.id } ?? 0) + 1
        return "Capture \(number) of \(captures.count) · \(capture.time) · Esc for live"
    }

    /// Called after a capture is added or removed.
    @ObservationIgnored var onChange: (() -> Void)?

    /// A capture of `frame`, or of just `area` of it (source pixels), copied now so it no longer
    /// depends on the stream. `image` is what was copied or saved, for the thumbnail and the size.
    /// `nil` when nothing of the frame is kept.
    static func capture(
        of frame: CapturedFrame, area: CGRect?, kind: String, image: CGImage, zoom: CGFloat, offset: CGPoint,
        selection: CGRect?
    ) -> RecentCapture? {
        guard let kept = frame.copiedForKeeping(area: area) else { return nil }
        return RecentCapture(
            frame: kept, kind: kind, imageSize: PixelSize(width: image.width, height: image.height), date: Date(),
            thumbnail: thumbnail(of: image), zoom: zoom, offset: offset, selection: selection)
    }

    /// Keeps `capture` as the newest; the oldest goes past the limit.
    func add(_ capture: RecentCapture) {
        captures.insert(capture, at: 0)
        if captures.count > Self.limit {
            // The shown one is never pushed out from under the Viewer: the oldest other one goes.
            let index = captures.lastIndex { $0.id != shownID } ?? captures.count - 1
            captures.remove(at: index)
        }
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

    /// `image` scaled down to fit the thumbnail box; a small image stays as it is.
    private static func thumbnail(of image: CGImage) -> CGImage? {
        let fit = min(1, thumbnailBox.width / CGFloat(image.width), thumbnailBox.height / CGFloat(image.height))
        guard fit < 1 else { return image }
        let width = max(1, Int((CGFloat(image.width) * fit).rounded()))
        let height = max(1, Int((CGFloat(image.height) * fit).rounded()))
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // A thumbnail, not a magnification: smoothing is right here.
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
