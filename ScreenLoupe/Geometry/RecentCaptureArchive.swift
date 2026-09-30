import Accelerate
import CoreGraphics
import Foundation
import ImageIO

/// How Recent Captures are kept on disk, so they outlast quitting, a crash or a restart: each
/// capture's pixels in a PNG of their own, named by its id, and an index with the rest — the list's
/// order, how each capture shows, its colour space, and which one the Viewer shows.
enum RecentCaptureArchive {
    static let indexName = "index.json"

    static func fileName(for id: UUID) -> String { "\(id.uuidString).png" }

    /// A capture as the index keeps it: everything but its pixels.
    struct Entry: Codable, Equatable, Sendable {
        var id: UUID
        var name = "Snapshot"
        var date = Date(timeIntervalSince1970: 0)
        var isFile = false
        var zoom: CGFloat?
        var offset = CGPoint.zero
        var selection: CGRect?
        var isLinked = false
        /// `nil`: the whole PNG, one pixel per point (`layout(_:pixels:)`).
        var layout: FrameLayout?
        var colorSpace: SavedColorSpace?
        /// A snapshot's top-left in the Capture Area when it was taken
        /// (`RecentCaptureRules.snapshotOrigin`); `nil` for an image, and for a snapshot kept before
        /// it was recorded.
        var areaOrigin: CGPoint?

        init(
            id: UUID, name: String, date: Date, isFile: Bool, zoom: CGFloat?, offset: CGPoint, selection: CGRect?,
            isLinked: Bool, layout: FrameLayout?, colorSpace: SavedColorSpace?, areaOrigin: CGPoint?
        ) {
            self.id = id
            self.name = name
            self.date = date
            self.isFile = isFile
            self.zoom = zoom
            self.offset = offset
            self.selection = selection
            self.isLinked = isLinked
            self.layout = layout
            self.colorSpace = colorSpace
            self.areaOrigin = areaOrigin
        }

        /// A key that is missing or unreadable keeps its default; only the id, which names the PNG,
        /// is required.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            name = c.value(.name, or: name)
            date = c.value(.date, or: date)
            isFile = c.value(.isFile, or: isFile)
            zoom = c.value(.zoom, or: zoom)
            offset = c.value(.offset, or: offset)
            selection = c.value(.selection, or: selection)
            isLinked = c.value(.isLinked, or: isLinked)
            layout = c.value(.layout, or: layout)
            colorSpace = c.value(.colorSpace, or: colorSpace)
            areaOrigin = c.value(.areaOrigin, or: areaOrigin)
        }
    }

    /// The list, newest first, and the capture the Viewer shows (`nil`: the live view).
    struct Index: Codable, Equatable, Sendable {
        var entries: [Entry] = []
        var shownID: UUID?

        init(entries: [Entry] = [], shownID: UUID? = nil) {
            self.entries = entries
            self.shownID = shownID
        }

        /// An unreadable entry is dropped; the others stay.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            entries = c.value(.entries, or: [Lenient<Entry>]()).compactMap(\.value)
            shownID = c.value(.shownID, or: nil)
        }
    }

    /// The colour space a capture's pixels are in, kept exactly: by name when the system names it
    /// (sRGB, Display P3), else as its ICC profile. Not left to the PNG's own tag: ImageIO writes a
    /// display's profile close to sRGB as PNG's sRGB chunk, and swaps others for a standard one.
    struct SavedColorSpace: Codable, Equatable, Sendable {
        var name: String?
        var iccProfile: Data?

        init?(_ space: CGColorSpace) {
            name = space.name as String?
            iccProfile = name == nil ? space.copyICCData() as Data? : nil
            guard name != nil || iccProfile != nil else { return nil }
        }

        /// `nil` when neither the name nor the profile makes an RGB space.
        var space: CGColorSpace? {
            let space =
                name.flatMap { CGColorSpace(name: $0 as CFString) }
                ?? iccProfile.flatMap { CGColorSpace(iccData: $0 as CFData) }
            return space?.model == .rgb ? space : nil
        }
    }

    /// Where a kept capture's picture sits in the Capture Area (`ViewerFrame.areaOrigin`): a
    /// snapshot's kept part where it was taken; the area's corner for an image, and for a snapshot
    /// kept before that was recorded.
    static func areaOrigin(_ entry: Entry) -> CGPoint {
        entry.isFile ? .zero : entry.areaOrigin ?? .zero
    }

    /// The entries to restore, newest first as kept: one per id, and no more than `limit`.
    static func restorable(_ entries: [Entry], limit: Int = RecentCaptureRules.limit) -> [Entry] {
        var seen = Set<UUID>()
        return Array(entries.filter { seen.insert($0.id).inserted }.prefix(limit))
    }

    /// The index's entries: the captures in the list, and those kept on disk but not in it — still
    /// being read at launch, or whose PNG couldn't be read, to try again at the next launch — each
    /// in its place among the kept ones as `order` (the kept ones' ids at launch, newest first) has
    /// them (`RecentCaptureRules.restoring`), so a save while they are read keeps the list's order.
    /// Within `limit`: `dropped`, the oldest ones not in the list past it, pushed out.
    static func indexEntries(
        listed: [Entry], unlisted: [Entry], order: [UUID], limit: Int = RecentCaptureRules.limit
    )
        -> (entries: [Entry], dropped: [Entry])
    {
        var entries = unlisted.reduce(listed) { RecentCaptureRules.restoring($1, into: $0, order: order, id: \.id) }
        var dropped: [Entry] = []
        let unlistedIDs = Set(unlisted.map(\.id))
        while entries.count > limit, let last = entries.lastIndex(where: { unlistedIDs.contains($0.id) }) {
            dropped.insert(entries.remove(at: last), at: 0)
        }
        return (entries, dropped)
    }

    /// The files in the folder the index doesn't name: a capture's PNG left by a crash between
    /// deleting it from the index and from the disk, or written after it was deleted.
    static func strayFiles(_ fileNames: [String], kept entries: [Entry]) -> [String] {
        let kept = Set(entries.map { fileName(for: $0.id) } + [indexName])
        return fileNames.filter { !kept.contains($0) }
    }

    /// How a capture whose PNG is `pixels` in size is laid out: as kept, when that fits the PNG —
    /// its pixels are the frame, inside the picture — else the whole PNG, one pixel per point.
    static func layout(_ saved: FrameLayout?, pixels: PixelSize) -> FrameLayout {
        guard let saved, saved.imageSize == pixels, saved.scale > 0,
            saved.imageOrigin.x >= 0, saved.imageOrigin.y >= 0,
            Int(saved.imageOrigin.x) + pixels.width <= saved.size.width,
            Int(saved.imageOrigin.y) + pixels.height <= saved.size.height
        else { return FrameLayout(image: pixels) }
        return saved
    }

    // MARK: Pixels

    /// Straight (not premultiplied) 8-bit BGRA in `space`: how the Viewer keeps an image's pixels,
    /// and a recent capture's.
    static func straightFormat(_ space: CGColorSpace) -> vImage_CGImageFormat {
        vImage_CGImageFormat(
            bitsPerComponent: 8, bitsPerPixel: 32, colorSpace: Unmanaged.passUnretained(space),
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.first.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
            version: 0, decode: nil, renderingIntent: .defaultIntent)
    }

    /// A PNG of `height` rows of `width` BGRA pixels at `base`, `bytesPerRow` apart, with the alpha
    /// as it is: every byte comes back from `copyPixels`. Tagged with `space` for other apps; the
    /// app itself keeps the space in the index (`SavedColorSpace`).
    static func pngData(
        bgra base: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int, space: CGColorSpace
    ) -> Data? {
        guard let provider = CGDataProvider(data: Data(bytes: base, count: bytesPerRow * height) as CFData) else {
            return nil
        }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.first.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard
            let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                space: space, bitmapInfo: info, provider: provider, decode: nil, shouldInterpolate: false,
                intent: .defaultIntent)
        else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// A kept PNG's image, `nil` when ImageIO can't read it.
    static func image(png data: Data) -> CGImage? {
        CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    }

    /// Writes `image`'s pixels as straight BGRA into `height` rows at `base`, `bytesPerRow` apart,
    /// in the image's own colour space, so no colour conversion touches them. Returns whether it
    /// could.
    static func copyPixels(of image: CGImage, into base: UnsafeMutableRawPointer, bytesPerRow: Int) -> Bool {
        var pixels = vImage_Buffer(
            data: base, height: vImagePixelCount(image.height), width: vImagePixelCount(image.width),
            rowBytes: bytesPerRow)
        var format = straightFormat(CGColorSpace.rgbSpace(forImageIn: image.colorSpace))
        return vImageBuffer_InitWithCGImage(&pixels, &format, nil, image, vImage_Flags(kvImageNoAllocate))
            == kvImageNoError
    }
}
