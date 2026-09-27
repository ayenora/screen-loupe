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
/// lone window over its background (docs/design.md, Screenshot studio).
enum StudioComposite {
    /// Whether `image` carries alpha, so a fill can show through where nothing was captured.
    static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: false
        default: true
        }
    }

    /// `image` in `space`: kept when already tagged with it, tagged when untagged, converted
    /// otherwise, so the pixels and the saved profile agree. `nil` when no context can be made.
    static func composited(_ image: CGImage, in space: CGColorSpace) -> CGImage? {
        let tagged = image.colorSpace == nil ? image.copy(colorSpace: space) ?? image : image
        if tagged.colorSpace == space { return tagged }
        guard
            let context = CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        context.interpolationQuality = .none
        context.draw(tagged, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    /// The backdrop's picture: `fill` over `size` pixels, opaque, in `space` — the display's, so
    /// the window server shows these pixels unchanged and a capture gives them back. Drawn as One
    /// Window's background is (`StudioFill.draw`), so a colour is the same pixels in both. `nil`
    /// when the size is empty or no context can be made.
    static func filled(_ fill: StudioFill, size: PixelSize, space: CGColorSpace) -> CGImage? {
        guard size.width > 0, size.height > 0,
            let context = CGContext(
                data: nil, width: size.width, height: size.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        fill.draw(in: context, size: CGSize(width: size.width, height: size.height))
        return context.makeImage()
    }

    /// A lone window's picture: `window` (already cut to its visible pixels) centred in a picture of
    /// `frame` pixels (`OneWindowPicture.pictureSize`) in `space` (`OneWindowPicture.centredOrigin`), drawn at its own size without
    /// interpolation, colour-matched into `space` as `composited` does. Over `fill`, the result is
    /// opaque; without one, the rest is transparent and the window's pixels, its shadow's alpha
    /// among them, are copied unchanged. `nil` when no context can be made or the window is larger
    /// than the frame.
    static func centred(
        _ window: CGImage, in frame: PixelSize, space: CGColorSpace, over fill: StudioFill?
    )
        -> CGImage?
    {
        let size = PixelSize(width: window.width, height: window.height)
        guard OneWindowPicture.fits(size, in: frame), frame.width > 0, frame.height > 0 else { return nil }
        let tagged = window.colorSpace == nil ? window.copy(colorSpace: space) ?? window : window
        let alpha: CGImageAlphaInfo = fill == nil ? .premultipliedFirst : .noneSkipFirst
        guard
            let context = CGContext(
                data: nil, width: frame.width, height: frame.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: alpha.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
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
        PixelSize(
            width: displays.map { Int(($0.globalFrame.width * $0.scale).rounded()) }.max() ?? 0,
            height: displays.map { Int(($0.globalFrame.height * $0.scale).rounded()) }.max() ?? 0)
    }
}
