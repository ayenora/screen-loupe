import AppKit
import CoreVideo
import ImageIO
import UniformTypeIdentifiers

/// Capture Source and Capture View images, the clipboard and PNG files (docs/product.md, Screenshots).
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

    /// Capture View: exactly the Viewer's viewport — its zoom, pan and background, the pixel grid
    /// when `grid` is given (docs/product.md, Pixel grid), and the visible reference layers, bottom
    /// first (docs/product.md, References).
    ///
    /// Drawn with the placement the renderer uses (`ZoomPanState.imageRect`), without interpolation
    /// when magnifying, so every source pixel is an exact N×N block at integer zoom.
    /// `checkerSquare` is in viewport pixels.
    static func viewImage(
        from frame: CapturedFrame, state: ZoomPanState, background: ViewerBackground, checkerSquare: CGFloat,
        grid: GridLines?, references: [(layer: ReferenceLayer, image: CGImage)] = [], colorSpace: CGColorSpace
    ) -> CGImage? {
        let width = Int(state.viewportSize.width.rounded())
        let height = Int(state.viewportSize.height.rounded())
        guard width > 0, height > 0,
            let image = frameImage(frame.pixelBuffer, colorSpace: colorSpace),
            let context = bitmapContext(width: width, height: height, colorSpace: colorSpace),
            fill(context, background: background, checkerSquare: checkerSquare, colorSpace: colorSpace)
        else { return nil }
        context.interpolationQuality = state.zoom >= 1 ? .none : .high
        let placed = state.imageRect(
            origin: frame.geometry.imageOrigin, size: CGSize(width: image.width, height: image.height))
        // The viewport is y down; CGContext is y up.
        let rect = CGRect(x: placed.minX, y: CGFloat(height) - placed.maxY, width: placed.width, height: placed.height)
        context.draw(image, in: rect)
        // The grid belongs to the frame: the renderer draws it in the frame's pass, under the layers.
        if let grid, let data = context.data {
            // The context's rows run top to bottom in memory, like the viewport.
            PixelGrid.draw(
                into: data.assumingMemoryBound(to: UInt8.self), width: width, height: height,
                bytesPerRow: context.bytesPerRow, imageRect: placed, zoom: state.zoom, lines: grid)
        }
        for (layer, reference) in references {
            drawReference(reference, layer: layer, live: image, frame: frame, state: state, into: context)
        }
        return context.makeImage()
    }

    /// One layer as the renderer draws it: over what is below, or as its difference from the live
    /// frame, at the layer's opacity.
    private static func drawReference(
        _ reference: CGImage, layer: ReferenceLayer, live: CGImage, frame: CapturedFrame, state: ZoomPanState,
        into context: CGContext
    ) {
        let height = CGFloat(context.height)
        func flipped(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
        }
        let placed = state.imageRect(origin: layer.origin, size: layer.frame.size)
        context.saveGState()
        defer { context.restoreGState() }
        context.setAlpha(CGFloat(layer.opacity))
        guard layer.blend == .difference else {
            context.draw(reference, in: flipped(placed))
            return
        }
        // The difference is taken against the live frame alone, only where the layer is on screen.
        let visible = placed.intersection(CGRect(origin: .zero, size: state.viewportSize)).integral
        guard !visible.isEmpty, let space = context.colorSpace,
            let scratch = bitmapContext(width: Int(visible.width), height: Int(visible.height), colorSpace: space)
        else { return }
        scratch.interpolationQuality = context.interpolationQuality
        func local(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX - visible.minX, y: visible.maxY - rect.maxY, width: rect.width, height: rect.height)
        }
        let livePlaced = state.imageRect(
            origin: frame.geometry.imageOrigin, size: CGSize(width: live.width, height: live.height))
        scratch.draw(live, in: local(livePlaced))
        scratch.setBlendMode(.difference)
        scratch.draw(reference, in: local(placed))
        // Where the reference is transparent the shader adds nothing; keep only its opaque part.
        scratch.setBlendMode(.destinationIn)
        scratch.draw(reference, in: local(placed))
        guard let difference = scratch.makeImage() else { return }
        context.clip(to: flipped(placed))
        context.draw(difference, in: flipped(visible))
    }

    /// The Viewer's background, squares counted from the top-left corner as the shader does.
    private static func fill(
        _ context: CGContext, background: ViewerBackground, checkerSquare: CGFloat, colorSpace: CGColorSpace
    ) -> Bool {
        func color(_ c: SIMD3<Double>) -> CGColor? {
            CGColor(colorSpace: colorSpace, components: [CGFloat(c.x), CGFloat(c.y), CGFloat(c.z), 1])
        }
        guard let first = color(background.components), let second = color(ViewerBackground.checkerDarkComponents)
        else { return false }
        let width = CGFloat(context.width)
        let height = CGFloat(context.height)
        context.setFillColor(first)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard background == .checkerboard, checkerSquare > 0 else { return true }
        context.setFillColor(second)
        for row in 0..<Int((height / checkerSquare).rounded(.up)) {
            for column in 0..<Int((width / checkerSquare).rounded(.up)) where (row + column) % 2 == 1 {
                context.fill(
                    CGRect(
                        x: CGFloat(column) * checkerSquare, y: height - CGFloat(row + 1) * checkerSquare,
                        width: checkerSquare, height: checkerSquare))
            }
        }
        return true
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
