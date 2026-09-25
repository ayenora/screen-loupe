import AppKit
import CoreVideo
import ImageIO
import UniformTypeIdentifiers

/// Capture Source images, the clipboard and PNG files (docs/product.md, Screenshots). Capture View is
/// rendered by the Viewer itself (`ViewerView.renderViewImage`).
enum ScreenshotExporter {
    // MARK: Images

    /// Capture Source: the Capture Area at its native resolution, without zoom.
    ///
    /// The frame's bytes are copied as they are, tagged with the source display's color space. When
    /// the area straddles two displays, the part on the other display stays transparent. Past
    /// `ImageBudget` only the area's top-left part.
    static func sourceImage(from frame: CapturedFrame, colorSpace: CGColorSpace) -> CGImage? {
        guard let image = frameImage(frame.pixelBuffer, colorSpace: colorSpace) else { return nil }
        let geometry = frame.geometry
        let area = geometry.areaSize
        let kept = ImageBudget.fitted(width: area.width, height: area.height)
        if geometry.imageOrigin == .zero, geometry.areaSize == frame.pixelSize {
            return kept == (area.width, area.height)
                ? image : image.cropping(to: CGRect(x: 0, y: 0, width: kept.width, height: kept.height))
        }
        guard let context = bitmapContext(width: kept.width, height: kept.height, colorSpace: colorSpace) else {
            return nil
        }
        // The context is y up: moving the area image down by the rows cut off below keeps its top.
        context.draw(image, in: geometry.imageRectInAreaImage.offsetBy(dx: 0, dy: CGFloat(kept.height - area.height)))
        return context.makeImage()
    }

    /// The frame's BGRA bytes as a `CGImage`, copied so the capture buffer can be reused.
    private static func frameImage(_ buffer: CVPixelBuffer, colorSpace: CGColorSpace) -> CGImage? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard let provider = CGDataProvider(data: Data(bytes: base, count: bytesPerRow * height) as CFData) else {
            return nil
        }
        // 32BGRA: little-endian 32-bit words with the (opaque) alpha first.
        let info = CGBitmapInfo(
            rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
            space: colorSpace, bitmapInfo: info, provider: provider, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent)
    }

    private static func bitmapContext(width: Int, height: Int, colorSpace: CGColorSpace) -> CGContext? {
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    // MARK: Output

    /// PNG with the image's color profile embedded.
    static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// Puts the image on the clipboard as PNG and TIFF, so both design tools and older apps can paste it.
    @MainActor
    @discardableResult
    static func copy(_ image: CGImage) -> Bool {
        guard let png = pngData(image) else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        if let tiff = NSBitmapImageRep(cgImage: image).tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
        return true
    }

    /// `Screen Loupe View 2026-09-24 at 14.20.05.png`, in the style of macOS screenshots, or
    /// `ScreenLoupe-View-20260924-142005.png`.
    static func fileName(kind: String, style: FileNameStyle, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        switch style {
        case .macOS:
            formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
            return "Screen Loupe \(kind) \(formatter.string(from: date)).png"
        case .compact:
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            return "ScreenLoupe-\(kind)-\(formatter.string(from: date)).png"
        }
    }
}
