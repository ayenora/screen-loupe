import AppKit
import CoreVideo
import ImageIO
import UniformTypeIdentifiers

/// Capture Source and Capture View images, the clipboard and PNG files (TASK.md §7).
enum ScreenshotExporter {
    // MARK: Images

    /// Capture Source: the Capture Area at its native resolution, without zoom.
    ///
    /// The frame's bytes are copied as they are, tagged with the source display's color space. When
    /// the area straddles two displays, the part on the other display stays transparent.
    static func sourceImage(from frame: CapturedFrame, colorSpace: CGColorSpace) -> CGImage? {
        guard let image = frameImage(frame.pixelBuffer, colorSpace: colorSpace) else { return nil }
        let geometry = frame.geometry
        if geometry.imageOrigin == .zero, geometry.areaSize == frame.pixelSize {
            return image
        }
        let area = geometry.areaSize
        guard let context = bitmapContext(width: area.width, height: area.height, colorSpace: colorSpace) else {
            return nil
        }
        // CGContext is y up; the image origin is y down from the area's top-left.
        let rect = CGRect(
            x: geometry.imageOrigin.x, y: CGFloat(area.height) - geometry.imageOrigin.y - CGFloat(image.height),
            width: CGFloat(image.width), height: CGFloat(image.height))
        context.draw(image, in: rect)
        return context.makeImage()
    }

    /// Capture View: exactly the Viewer's viewport — its zoom, pan and background.
    ///
    /// Drawn with the placement the renderer uses (`ZoomPanState.imageRect`), without interpolation
    /// when magnifying, so every source pixel is an exact N×N block at integer zoom.
    static func viewImage(
        from frame: CapturedFrame, state: ZoomPanState, background: CGColor, colorSpace: CGColorSpace
    ) -> CGImage? {
        let width = Int(state.viewportSize.width.rounded())
        let height = Int(state.viewportSize.height.rounded())
        guard width > 0, height > 0,
            let image = frameImage(frame.pixelBuffer, colorSpace: colorSpace),
            let context = bitmapContext(width: width, height: height, colorSpace: colorSpace)
        else { return nil }
        context.setFillColor(background)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = state.zoom >= 1 ? .none : .high
        let placed = state.imageRect(
            origin: frame.geometry.imageOrigin, size: CGSize(width: image.width, height: image.height))
        // The viewport is y down; CGContext is y up.
        let rect = CGRect(x: placed.minX, y: CGFloat(height) - placed.maxY, width: placed.width, height: placed.height)
        context.draw(image, in: rect)
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

    /// `Screen Loupe View 2026-09-24 at 14.20.05.png`, in the style of macOS screenshots.
    static func fileName(kind: String, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Screen Loupe \(kind) \(formatter.string(from: date)).png"
    }
}
