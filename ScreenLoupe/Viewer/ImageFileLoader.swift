import Accelerate
import CoreVideo
import ImageIO
import UniformTypeIdentifiers

/// Reads image files, and pasted image data, for the Viewer: an opened image and reference layers (References). Called
/// off the main actor: a large file takes a while
/// to decode.
enum ImageFileLoader {
    /// The image files Open Image and references take: every type ImageIO reads, but not PDF. Read
    /// once: menu validation asks for them each time the menu opens.
    static let openableTypes: [UTType] = {
        let identifiers = CGImageSourceCopyTypeIdentifiers() as? [String] ?? []
        return identifiers.compactMap { UTType($0) }.filter { !$0.conforms(to: .pdf) }
    }()

    /// The file's first frame, upright as its EXIF orientation says, and past `ImageBudget` just its
    /// top-left part. `nil` when ImageIO can't read it.
    static func image(at url: URL) -> CGImage? {
        CGImageSourceCreateWithURL(url as CFURL, nil).flatMap(image(from:))
    }

    /// Pasted image data read as a file is (`image(at:)`).
    static func image(data: Data) -> CGImage? {
        CGImageSourceCreateWithData(data as CFData, nil).flatMap(image(from:))
    }

    private static func image(from source: CGImageSource) -> CGImage? {
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        guard let stored = CGImageSourceCreateImageAtIndex(source, 0, options) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = ImageOrientation(exif: properties?[kCGImagePropertyOrientation] as? Int ?? 1)
        guard let image = orientation.isUpright ? stored : upright(stored, orientation) else { return nil }
        let kept = ImageBudget.fitted(width: image.width, height: image.height)
        guard kept != (image.width, image.height) else { return image }
        return image.cropping(to: CGRect(x: 0, y: 0, width: kept.width, height: kept.height))
    }

    /// `image` turned upright, on its straight pixels, so values and transparency stay exact (ImageIO's
    /// own transform premultiplies them).
    private static func upright(_ image: CGImage, _ orientation: ImageOrientation) -> CGImage? {
        let space = CGColorSpace.rgbSpace(forImageIn: image.colorSpace)
        var format = RecentCaptureArchive.straightFormat(space)
        let flags = vImage_Flags(kvImageNoFlags)
        var stored = vImage_Buffer()
        guard vImageBuffer_InitWithCGImage(&stored, &format, nil, image, flags) == kvImageNoError else { return nil }
        defer { free(stored.data) }
        if orientation.mirrored, vImageHorizontalReflect_ARGB8888(&stored, &stored, flags) != kvImageNoError {
            return nil
        }
        guard orientation.quarterTurns > 0 else {
            return vImageCreateCGImageFromBuffer(&stored, &format, nil, nil, flags, nil)?.takeRetainedValue()
        }
        var turned = vImage_Buffer()
        let (width, height) = orientation.swapsSides ? (stored.height, stored.width) : (stored.width, stored.height)
        guard vImageBuffer_Init(&turned, height, width, 32, flags) == kvImageNoError else { return nil }
        defer { free(turned.data) }
        // vImage counts turns counterclockwise.
        let counterclockwise = UInt8((4 - orientation.quarterTurns) % 4)
        var background: [UInt8] = [0, 0, 0, 0]
        guard vImageRotate90_ARGB8888(&stored, &turned, counterclockwise, &background, flags) == kvImageNoError
        else { return nil }
        return vImageCreateCGImageFromBuffer(&turned, &format, nil, nil, flags, nil)?.takeRetainedValue()
    }

    /// The image file at `url` as a picture of its own: `image(at:)` copied once
    /// into a buffer like a recent capture's, one pixel per point, as straight (not premultiplied)
    /// BGRA in the image's own colour space (`CGColorSpace.rgbSpace(forImageIn:)`), so its values and
    /// its transparency stay as they are. More than 8 bits per component are rounded to 8. `nil`
    /// when ImageIO can't read it. With it, the thumbnail for its Recent Captures row.
    @concurrent
    static func frame(at url: URL) async -> (frame: ViewerFrame, thumbnail: CGImage?)? {
        image(at: url).flatMap(frame(of:))
    }

    /// Pasted image data as a picture of its own, as a file is (`frame(at:)`).
    @concurrent
    static func frame(data: Data) async -> (frame: ViewerFrame, thumbnail: CGImage?)? {
        image(data: data).flatMap(frame(of:))
    }

    private static func frame(of image: CGImage) -> (frame: ViewerFrame, thumbnail: CGImage?)? {
        guard let buffer = ViewerFrame.makeBuffer(width: image.width, height: image.height) else { return nil }
        let space = CGColorSpace.rgbSpace(forImageIn: image.colorSpace)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        // CoreGraphics draws only into premultiplied 8-bit contexts; vImage writes straight alpha,
        // converting only when the image's space isn't the buffer's.
        var pixels = vImage_Buffer(
            data: CVPixelBufferGetBaseAddress(buffer), height: vImagePixelCount(image.height),
            width: vImagePixelCount(image.width), rowBytes: CVPixelBufferGetBytesPerRow(buffer))
        var format = RecentCaptureArchive.straightFormat(space)
        guard
            vImageBuffer_InitWithCGImage(&pixels, &format, nil, image, vImage_Flags(kvImageNoAllocate))
                == kvImageNoError
        else { return nil }
        let layout = FrameLayout(image: PixelSize(width: image.width, height: image.height))
        let frame = ViewerFrame(
            pixelBuffer: buffer, layout: layout, displayID: nil, imageColorSpace: space, hasAlpha: true)
        return (frame, RecentCaptures.thumbnail(of: image))
    }
}
