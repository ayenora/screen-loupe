import CoreGraphics
import Foundation
import ImageIO

/// A picture the Viewer holds — a recent capture or the frozen frame — made a reference layer, to
/// compare the screen with itself as it was: whatever changed since glows in Difference.
enum CaptureReference {
    /// What the picture is, for the layer's name.
    enum Source: Equatable, Sendable {
        /// A snapshot of the screen, taken at `date`.
        case snapshot(date: Date)
        /// An image file or a pasted image, with its name.
        case image(name: String)
        /// The frozen frame, frozen at `date`.
        case frozenFrame(date: Date)
    }

    /// The layer for a picture laid out as `layout` whose top-left sits at `pictureOrigin` in the
    /// Capture Area (`ViewerFrame.areaOrigin`), its pixels in the project as `fileName`: on top of
    /// the others in Difference at full opacity, so what changed shows at once; one image pixel per
    /// source pixel; and its pixels where they are in the area — a snapshot's where they were taken,
    /// the frozen frame's over the area, an image's at the top-left, as Add… puts it. The frame's own
    /// offset in its picture (`FrameLayout.imageOrigin`, an area straddling two displays) counts
    /// too. Past `ImageBudget` only the top-left part is kept, as for any added image.
    static func layer(
        _ source: Source, layout: FrameLayout, pictureOrigin: CGPoint, id: UUID, fileName: String,
        timeZone: TimeZone
    ) -> ReferenceLayer {
        let kept = ImageBudget.fitted(width: layout.imageSize.width, height: layout.imageSize.height)
        var layer = ReferenceLayer(
            id: id, name: name(source, timeZone: timeZone), fileName: fileName,
            imageSize: CGSize(width: kept.width, height: kept.height),
            origin: PictureInArea.areaPoint(layout.imageOrigin, pictureOrigin: pictureOrigin))
        layer.opacity = 1
        layer.blend = .difference
        return layer
    }

    /// The layer's name, after its row: "Snapshot 14:32:05", the image's name, or "Frozen frame
    /// 14:32:05" — the 24-hour time it was taken in `timeZone`, to tell several apart.
    static func name(_ source: Source, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm:ss"
        switch source {
        case .snapshot(let date): return "Snapshot \(formatter.string(from: date))"
        case .image(let name): return name
        case .frozenFrame(let date): return "Frozen frame \(formatter.string(from: date))"
        }
    }

    /// A TIFF of `height` rows of `width` BGRA pixels at `base`, `bytesPerRow` apart, in `space`:
    /// the layer's copy in the project. TIFF, not PNG, as it keeps the colour profile exactly —
    /// ImageIO swaps a display's profile in a PNG for a standard one — so a pixel that hasn't
    /// changed matches the live one exactly in Difference. The alpha counts only for `hasAlpha` (an
    /// image's transparency); a frame of the screen is opaque, whatever its alpha bytes hold.
    /// LZW-compressed, lossless.
    static func tiffData(
        bgra base: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int, space: CGColorSpace, hasAlpha: Bool
    ) -> Data? {
        guard let provider = CGDataProvider(data: Data(bytes: base, count: bytesPerRow * height) as CFData) else {
            return nil
        }
        let alpha: CGImageAlphaInfo = hasAlpha ? .first : .noneSkipFirst
        let info = CGBitmapInfo(rawValue: alpha.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard
            let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                space: space, bitmapInfo: info, provider: provider, decode: nil, shouldInterpolate: false,
                intent: .defaultIntent)
        else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.tiff" as CFString, 1, nil)
        else { return nil }
        let lzw = 5
        let options = [kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: lzw]] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
