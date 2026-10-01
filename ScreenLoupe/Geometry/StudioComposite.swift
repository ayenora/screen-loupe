import CoreGraphics

/// A studio background ready to draw (`StudioBackground` with its image decoded).
enum StudioFill {
    case color(BackgroundColor)
    case gradient(BackgroundGradient)
    case image(CGImage)

    /// Fills a picture of `size` pixels in `context`; CoreGraphics colour-matches from sRGB, or from
    /// the image's own space, into the context's. An image is laid on white, so its transparent
    /// parts are white, not black.
    func draw(in context: CGContext, size: CGSize) {
        let bounds = CGRect(origin: .zero, size: size)
        switch self {
        case .color(let color):
            context.setFillColor(color.cgColor)
            context.fill(bounds)
        case .gradient(let colors):
            guard
                let gradient = CGGradient(
                    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                    colors: [colors.top.cgColor, colors.bottom.cgColor] as CFArray, locations: [0, 1])
            else { return }
            let line = StudioBackground.gradientLine(in: size)
            context.drawLinearGradient(
                gradient, start: line.start, end: line.end,
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        case .image(let image):
            context.setFillColor(BackgroundColor.white.cgColor)
            context.fill(bounds)
            context.interpolationQuality = .high
            context.draw(
                image, in: StudioBackground.imageRect(CGSize(width: image.width, height: image.height), filling: size))
        }
    }
}

extension BackgroundColor {
    var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
}

/// Puts a studio picture into the display's colour space, draws the studio's backdrop, and lays a
/// lone window over its background.
enum StudioComposite {
    /// Whether `image` carries alpha, so a fill can show through where nothing was captured.
    static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: false
        default: true
        }
    }

    /// Whether every pixel of `image` is opaque: true without reading when it has no alpha
    /// (`hasAlpha`); otherwise its alpha is drawn once into an 8-bit alpha-only bitmap, with no
    /// colour work, and read until the first pixel under 255. A capture comes with alpha although
    /// every pixel is opaque, so the alpha info alone doesn't tell. False when no context can be
    /// made, so alpha is kept. Reads every pixel of a large picture: call it off the main actor.
    static func isOpaque(_ image: CGImage) -> Bool {
        guard hasAlpha(image) else { return true }
        let width = image.width
        let height = image.height
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue),
            let data = context.data
        else { return false }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let rowBytes = context.bytesPerRow
        for row in 0..<height {
            let alpha = UnsafeBufferPointer(
                start: (data + row * rowBytes).assumingMemoryBound(to: UInt8.self), count: width)
            if alpha.contains(where: { $0 != 255 }) { return false }
        }
        return true
    }

    /// `image` in `space`: kept when already tagged with it, tagged when untagged, converted
    /// otherwise, so the pixels and the saved profile agree. `nil` when no context can be made.
    static func converted(_ image: CGImage, to space: CGColorSpace) -> CGImage? {
        let tagged = Self.tagged(image, with: space)
        if tagged.colorSpace == space { return tagged }
        guard
            let context = Self.context(
                PixelSize(width: image.width, height: image.height), space: space, alpha: .noneSkipFirst)
        else { return nil }
        context.interpolationQuality = .none
        context.draw(tagged, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    /// `image`, tagged with `space` when it has no colour space of its own.
    private static func tagged(_ image: CGImage, with space: CGColorSpace) -> CGImage {
        image.colorSpace == nil ? image.copy(colorSpace: space) ?? image : image
    }

    /// An 8-bit BGRA bitmap context of `size` pixels in `space`.
    private static func context(_ size: PixelSize, space: CGColorSpace, alpha: CGImageAlphaInfo) -> CGContext? {
        CGContext(
            data: nil, width: size.width, height: size.height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: alpha.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    }

    /// The backdrop's picture: `fill` over `size` pixels, opaque, in `space` — the display's, so
    /// the window server shows these pixels unchanged and a capture gives them back. Drawn as One
    /// Window's background is (`StudioFill.draw`), so a colour is the same pixels in both. `nil`
    /// when the size is empty or no context can be made.
    static func filled(_ fill: StudioFill, size: PixelSize, space: CGColorSpace) -> CGImage? {
        guard size.width > 0, size.height > 0, let context = Self.context(size, space: space, alpha: .noneSkipFirst)
        else { return nil }
        fill.draw(in: context, size: CGSize(width: size.width, height: size.height))
        return context.makeImage()
    }

    /// A lone window's picture: `window` (already cut to its visible pixels) centred in a picture of
    /// `frame` pixels (`OneWindowPicture.pictureSize`) in `space` (`OneWindowPicture.centredOrigin`),
    /// drawn at its own size without interpolation, colour-matched into `space` as `converted` does.
    /// Over `fill`, the result is opaque; without one, the rest is transparent and the window's
    /// pixels, its shadow's alpha among them, are copied unchanged. `nil` when no context can be
    /// made or the window is larger than the frame.
    static func centred(
        _ window: CGImage, in frame: PixelSize, space: CGColorSpace, over fill: StudioFill?
    )
        -> CGImage?
    {
        let size = PixelSize(width: window.width, height: window.height)
        guard OneWindowPicture.fits(size, in: frame), frame.width > 0, frame.height > 0 else { return nil }
        let tagged = Self.tagged(window, with: space)
        guard
            let context = Self.context(frame, space: space, alpha: fill == nil ? .premultipliedFirst : .noneSkipFirst)
        else { return nil }
        fill?.draw(in: context, size: CGSize(width: frame.width, height: frame.height))
        let origin = OneWindowPicture.centredOrigin(of: size, in: frame)
        // CoreGraphics counts y from the bottom.
        let rect = CGRect(
            x: origin.x, y: frame.height - origin.y - size.height, width: size.width, height: size.height)
        context.interpolationQuality = .none
        context.draw(tagged, in: rect)
        return context.makeImage()
    }

    /// The longest side, in pixels, a background image of `imageSize` (upright) needs to be
    /// decoded at so it still covers a whole display of `display` pixels — the backdrop, and so any
    /// picture — without being scaled up: the image scaled to cover it, but never larger than the
    /// image. At least 1.
    static func backgroundMaxPixelSize(image imageSize: PixelSize, display: PixelSize) -> Int {
        let longest = max(imageSize.width, imageSize.height)
        guard imageSize.width > 0, imageSize.height > 0 else { return max(longest, 1) }
        // The cover scale as a fraction, compared and rounded in whole numbers: width / width when
        // that side leads, else height / height.
        let (numerator, denominator) =
            display.width * imageSize.height >= display.height * imageSize.width
            ? (display.width, imageSize.width) : (display.height, imageSize.height)
        guard numerator < denominator else { return longest }
        return max((longest * numerator + denominator - 1) / denominator, 1)
    }

    /// The largest width and the largest height, in pixels, of `displays`: a backdrop, or a
    /// picture, on any of them is no larger.
    static func largestPicture(on displays: [DisplayInfo]) -> PixelSize {
        let sizes = displays.map(StudioBackdrop.pixelSize(of:))
        return PixelSize(width: sizes.map(\.width).max() ?? 0, height: sizes.map(\.height).max() ?? 0)
    }
}
