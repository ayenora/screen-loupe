import CoreGraphics
import Foundation
import ImageIO

/// How the Screenshot studio's pictures are written, on the clipboard and in files: the format, the colour space and
/// the scale. The Viewer's Copy and Save don't use it.
struct StudioOutput: Codable, Equatable, Sendable {
    enum Format: String, Codable, CaseIterable, Sendable {
        case png, jpeg, heic

        var title: String {
            switch self {
            case .png: "PNG"
            case .jpeg: "JPEG"
            case .heic: "HEIC"
            }
        }

        var fileExtension: String {
            switch self {
            case .png: "png"
            case .jpeg: "jpg"
            case .heic: "heic"
            }
        }

        /// The uniform type identifier, for ImageIO, the save panel and the pasteboard.
        var typeIdentifier: String {
            switch self {
            case .png: "public.png"
            case .jpeg: "public.jpeg"
            case .heic: "public.heic"
            }
        }

        /// JPEG has no alpha: a transparent picture is laid on white for it. HEIC keeps it.
        var keepsAlpha: Bool { self != .jpeg }
    }

    enum Colors: String, Codable, CaseIterable, Sendable {
        /// Converted to sRGB, and tagged as sRGB the format's own way (`encoded(_:as:)`).
        case sRGB = "srgb"
        /// Kept in the display's colour space, its ICC profile embedded.
        case display

        var title: String { self == .sRGB ? "sRGB" : "Display" }
    }

    enum Scale: String, Codable, CaseIterable, Sendable {
        /// The display's pixels, as captured.
        case native
        /// One pixel per point: halved on a 2× display.
        case points

        var title: String { self == .native ? "Native Pixels" : "1× (Points)" }
    }

    var format = Format.png
    var colors = Colors.sRGB
    var scale = Scale.native

    /// The lossy formats' quality, fixed.
    static let quality = 0.9

    init(format: Format = .png, colors: Colors = .sRGB, scale: Scale = .native) {
        self.format = format
        self.colors = colors
        self.scale = scale
    }

    /// Each choice on its own: a missing or unknown one keeps its default, the others load as saved.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = StudioOutput()
        format = c.value(.format, or: d.format)
        colors = c.value(.colors, or: d.colors)
        scale = c.value(.scale, or: d.scale)
    }

    /// The picture's size for `pixels` captured at `pointScale` pixels per point. At 1× each side
    /// is its length in points, rounded to the nearest pixel with a half pixel up (1441 px at 2×
    /// gives 721), and at least one pixel; a display of 1× or less stays as it is.
    func pixelSize(of pixels: PixelSize, pointScale: CGFloat) -> PixelSize {
        guard scale == .points, pointScale > 1 else { return pixels }
        func side(_ length: Int) -> Int {
            max(1, Int((CGFloat(length) / pointScale).rounded(.toNearestOrAwayFromZero)))
        }
        return PixelSize(width: side(pixels.width), height: side(pixels.height))
    }

    /// `image`, captured at `pointScale`, as it is written: in sRGB or kept in its own (the
    /// display's) space, scaled to 1× or not, and laid on white when the format has no alpha. An
    /// image that needs none of that is returned as it is, so its pixels stay exact. Scaling is
    /// CoreGraphics' `.medium` interpolation, an area average: at exactly 2× each pixel is the mean
    /// of the four it covers, so edges stay without ringing. `nil` when no context can be made.
    func prepared(_ image: CGImage, pointScale: CGFloat) -> CGImage? {
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        let space = colors == .sRGB ? sRGB : image.colorSpace ?? sRGB
        let native = PixelSize(width: image.width, height: image.height)
        let size = pixelSize(of: native, pointScale: pointScale)
        let hasAlpha = StudioComposite.hasAlpha(image)
        let keepsAlpha = hasAlpha && format.keepsAlpha
        if size == native, keepsAlpha == hasAlpha, image.colorSpace == space { return image }
        guard
            let context = CGContext(
                data: nil, width: size.width, height: size.height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: (keepsAlpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue)
        else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        if !keepsAlpha {
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            context.fill(bounds)
        }
        context.interpolationQuality = size == native ? .none : .medium
        context.draw(image, in: bounds)
        return context.makeImage()
    }

    /// `image` encoded as `format`, with its colour space and nothing personal: 72 DPI, the lossy
    /// formats at `quality`, and no date, device, software or location. What ImageIO adds on its
    /// own, and its options can't leave out: an Exif block with the pixel size (and, for sRGB, the
    /// Exif colour space); HEIC's Orientation of 1; JPEG's JFIF header with density units 0 and an
    /// APP13 block holding an empty IPTC digest. sRGB is tagged the format's own way — PNG's sRGB
    /// chunk, JPEG's Exif colour space, HEIC's colour information — not as an ICC profile; any
    /// other space is embedded as its ICC profile. `nil` when ImageIO can't write the format.
    static func encoded(_ image: CGImage, as format: Format) -> Data? {
        encoded(image, type: format.typeIdentifier, lossy: format != .png)
    }

    private static func encoded(_ image: CGImage, type: String, lossy: Bool) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type as CFString, 1, nil) else { return nil }
        var properties: [CFString: Any] = [kCGImagePropertyDPIWidth: 72, kCGImagePropertyDPIHeight: 72]
        if lossy { properties[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// The clipboard's types for `format`, in order: the format's own; for JPEG and HEIC then PNG,
    /// since many apps paste neither; and TIFF last, for older apps.
    static func pasteboardTypes(for format: Format) -> [String] {
        let png = Format.png.typeIdentifier
        let tiff = "public.tiff"
        return format == .png ? [png, tiff] : [format.typeIdentifier, png, tiff]
    }

    /// A studio picture as written: the prepared picture, its data in the format, and, when it goes
    /// to the clipboard, the data for each of `pasteboardTypes`, all from the same picture.
    struct Written: Sendable {
        var picture: CGImage
        var data: Data
        var pasteboard: [(type: String, data: Data)]
    }

    /// `image` prepared and encoded (`prepared(_:pointScale:)`, `encoded(_:as:)`), with the
    /// clipboard's data only `forPasteboard`. `nil` when any of it can't be made.
    func written(_ image: CGImage, pointScale: CGFloat, forPasteboard: Bool) -> Written? {
        guard let picture = prepared(image, pointScale: pointScale),
            let data = Self.encoded(picture, as: format)
        else { return nil }
        var pasteboard: [(type: String, data: Data)] = []
        if forPasteboard {
            for type in Self.pasteboardTypes(for: format) {
                let typeData =
                    type == format.typeIdentifier ? data : Self.encoded(picture, type: type, lossy: false)
                guard let typeData else { return nil }
                pasteboard.append((type, typeData))
            }
        }
        return Written(picture: picture, data: data, pasteboard: pasteboard)
    }
}
