import CoreGraphics
import Foundation
import ImageIO
import Testing

private let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
private let displayP3 = CGColorSpace(name: CGColorSpace.displayP3)!

/// Premultiplied BGRA pixels, as ScreenCaptureKit and the studio's compositing give them: `pixels`
/// row by row from the top, each `[blue, green, red, alpha]`. `alpha: false` makes an opaque image.
private func picture(
    width: Int, height: Int, space: CGColorSpace, alpha: Bool = true, _ pixels: [[UInt8]]
) -> CGImage {
    let provider = CGDataProvider(data: Data(pixels.flatMap { $0 }) as CFData)!
    let alphaInfo = alpha ? CGImageAlphaInfo.premultipliedFirst : .noneSkipFirst
    return CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: space,
        bitmapInfo: CGBitmapInfo(rawValue: alphaInfo.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
}

/// An opaque picture of one colour, `[blue, green, red]`.
private func plain(width: Int, height: Int, space: CGColorSpace, _ bgr: [UInt8]) -> CGImage {
    picture(
        width: width, height: height, space: space, alpha: false,
        Array(repeating: bgr + [255], count: width * height))
}

/// The pixels of `image` as `[blue, green, red, alpha]` from the top row, premultiplied, read in
/// `space` with no conversion when it is the image's own.
private func pixels(_ image: CGImage, in space: CGColorSpace) -> [[UInt8]] {
    let context = CGContext(
        data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let data = context.data!.assumingMemoryBound(to: UInt8.self)
    return (0..<(image.width * image.height)).map { index in (0..<4).map { data[index * 4 + $0] } }
}

private func near(_ pixel: [UInt8], _ expected: [Int], within tolerance: Int) -> Bool {
    zip(pixel, expected).allSatisfy { abs(Int($0) - $1) <= tolerance }
}

/// What ImageIO reads back from an encoded picture.
private struct Decoded {
    let image: CGImage
    let properties: [String: Any]
    /// Every metadata tag's path, as `prefix:name`, nested ones included.
    let tagPaths: [String]

    init(_ data: Data) throws {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]) ?? [:]
        var paths: [String] = []
        if let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil) {
            CGImageMetadataEnumerateTagsUsingBlock(
                metadata, nil, [kCGImageMetadataEnumerateRecursively: true] as CFDictionary
            ) { path, _ in
                paths.append(path as String)
                return true
            }
        }
        tagPaths = paths
    }

    func dictionary(_ key: CFString) -> [String: Any]? { properties[key as String] as? [String: Any] }
}

struct StudioOutputSettingsTests {
    /// Decodes `output` as the settings do: `value(_:or:)` with the defaults as the fallback.
    private struct Saved: Decodable {
        let output: StudioOutput

        private enum CodingKeys: String, CodingKey { case output }

        init(from decoder: Decoder) throws {
            output = try decoder.container(keyedBy: CodingKeys.self).value(.output, or: StudioOutput())
        }
    }

    private func decoded(_ json: String) throws -> StudioOutput {
        try JSONDecoder().decode(Saved.self, from: Data(json.utf8)).output
    }

    @Test func theDefaultsArePNGInSRGBAtNativePixels() {
        #expect(StudioOutput() == StudioOutput(format: .png, colors: .sRGB, scale: .native))
    }

    @Test func theChoicesAndTheirTitles() {
        #expect(StudioOutput.Format.allCases.map(\.title) == ["PNG", "JPEG", "HEIC"])
        #expect(StudioOutput.Colors.allCases.map(\.title) == ["sRGB", "Display"])
        #expect(StudioOutput.Scale.allCases.map(\.title) == ["Native Pixels", "1× (Points)"])
    }

    @Test func eachFormatHasItsExtensionTypeAndAlpha() {
        #expect(StudioOutput.Format.allCases.map(\.fileExtension) == ["png", "jpg", "heic"])
        #expect(StudioOutput.Format.allCases.map(\.typeIdentifier) == ["public.png", "public.jpeg", "public.heic"])
        #expect(StudioOutput.Format.allCases.map(\.keepsAlpha) == [true, false, true])
    }

    @Test func theOutputIsSavedByName() throws {
        let output = StudioOutput(format: .heic, colors: .display, scale: .points)
        let json = String(decoding: try JSONEncoder().encode(output), as: UTF8.self)
        #expect(json.contains("\"format\":\"heic\""))
        #expect(json.contains("\"colors\":\"display\""))
        #expect(json.contains("\"scale\":\"points\""))
        #expect(try decoded("{\"output\": \(json)}") == output)
    }

    @Test func aMissingOrUnknownChoiceKeepsItsDefaultAndTheOthersLoad() throws {
        #expect(try decoded("{}") == StudioOutput())
        #expect(try decoded("{\"output\": {}}") == StudioOutput())
        #expect(
            try decoded("{\"output\": {\"format\": \"webp\", \"colors\": \"display\", \"scale\": \"points\"}}")
                == StudioOutput(format: .png, colors: .display, scale: .points))
        #expect(
            try decoded("{\"output\": {\"format\": \"jpeg\", \"colors\": 3, \"scale\": null}}")
                == StudioOutput(format: .jpeg, colors: .sRGB, scale: .native))
        #expect(try decoded("{\"output\": {\"format\": \"heic\"}}") == StudioOutput(format: .heic))
        #expect(try decoded("{\"output\": \"png\"}") == StudioOutput())
        #expect(try decoded("{\"output\": [1, 2]}") == StudioOutput())
    }
}

struct StudioOutputScaleTests {
    private let native = StudioOutput(scale: .native)
    private let points = StudioOutput(scale: .points)

    @Test func nativePixelsAreKeptOnEveryDisplay() {
        let size = PixelSize(width: 2881, height: 1801)
        #expect(native.pixelSize(of: size, pointScale: 2) == size)
        #expect(native.pixelSize(of: size, pointScale: 1) == size)
    }

    @Test func oneXHalvesAPictureOfATwoXDisplay() {
        #expect(
            points.pixelSize(of: PixelSize(width: 2880, height: 1800), pointScale: 2)
                == PixelSize(width: 1440, height: 900))
    }

    @Test func anOddPixelSizeRoundsItsHalfPointUp() {
        #expect(
            points.pixelSize(of: PixelSize(width: 2881, height: 1799), pointScale: 2)
                == PixelSize(width: 1441, height: 900))
        #expect(points.pixelSize(of: PixelSize(width: 3, height: 5), pointScale: 2) == PixelSize(width: 2, height: 3))
    }

    @Test func aSideNeverGoesUnderOnePixel() {
        #expect(points.pixelSize(of: PixelSize(width: 1, height: 1), pointScale: 2) == PixelSize(width: 1, height: 1))
        #expect(points.pixelSize(of: PixelSize(width: 1, height: 1), pointScale: 3) == PixelSize(width: 1, height: 1))
    }

    @Test func aThreeXDisplayRoundsToTheNearestPixel() {
        #expect(
            points.pixelSize(of: PixelSize(width: 100, height: 101), pointScale: 3)
                == PixelSize(width: 33, height: 34))
    }

    @Test func aOneXDisplayIsLeftAsItIs() {
        let size = PixelSize(width: 1441, height: 901)
        #expect(points.pixelSize(of: size, pointScale: 1) == size)
    }

    @Test func thePreparedPictureHasTheScaledSize() throws {
        let image = plain(width: 7, height: 5, space: sRGB, [10, 20, 30])
        let scaled = try #require(points.prepared(image, pointScale: 2))
        #expect((scaled.width, scaled.height) == (4, 3))
        let same = try #require(points.prepared(image, pointScale: 1))
        #expect(same === image)
    }

    @Test func scalingAveragesTheFourPixelsEachOneCovers() throws {
        // Gray 0, 100, 200 and 255: their mean is 138.75.
        let image = picture(
            width: 2, height: 2, space: sRGB, alpha: false,
            [[0, 0, 0, 255], [100, 100, 100, 255], [200, 200, 200, 255], [255, 255, 255, 255]])
        let scaled = try #require(points.prepared(image, pointScale: 2))
        #expect(near(pixels(scaled, in: sRGB)[0], [139, 139, 139, 255], within: 1))
    }

    @Test func scalingKeepsBlocksOfTwoByTwoExactWithoutRinging() throws {
        // 2 × 2 blocks of red and blue in a checkerboard: each becomes one pixel of its colour.
        let red: [UInt8] = [0, 0, 255, 255]
        let blue: [UInt8] = [255, 0, 0, 255]
        let rows = (0..<8).map { y in (0..<8).map { x in (x / 2 + y / 2).isMultiple(of: 2) ? red : blue } }
        let image = picture(width: 8, height: 8, space: sRGB, alpha: false, rows.flatMap { $0 })
        let scaled = try #require(points.prepared(image, pointScale: 2))
        let expected = (0..<4).flatMap { y in (0..<4).map { x in (x + y).isMultiple(of: 2) ? red : blue } }
        #expect(pixels(scaled, in: sRGB) == expected)
    }

    @Test func aOnePixelCheckerboardBecomesEvenGray() throws {
        let white: [UInt8] = [255, 255, 255, 255]
        let black: [UInt8] = [0, 0, 0, 255]
        let rows = (0..<6).flatMap { y in (0..<6).map { x in (x + y).isMultiple(of: 2) ? white : black } }
        let scaled = try #require(points.prepared(picture(width: 6, height: 6, space: sRGB, rows), pointScale: 2))
        #expect(pixels(scaled, in: sRGB).allSatisfy { near($0, [128, 128, 128, 255], within: 1) })
    }

    @Test func scalingKeepsTransparency() throws {
        // A transparent column beside an opaque red one: half-transparent red.
        let image = picture(
            width: 2, height: 2, space: sRGB, [[0, 0, 255, 255], [0, 0, 0, 0], [0, 0, 255, 255], [0, 0, 0, 0]])
        let scaled = try #require(points.prepared(image, pointScale: 2))
        #expect(StudioComposite.hasAlpha(scaled))
        #expect(near(pixels(scaled, in: sRGB)[0], [0, 0, 128, 128], within: 1))
    }
}

struct StudioOutputColorTests {
    @Test func aPictureNeedingNothingIsKeptAsItIs() throws {
        let srgbImage = plain(width: 3, height: 2, space: sRGB, [1, 2, 3])
        #expect(StudioOutput().prepared(srgbImage, pointScale: 2) === srgbImage)
        let p3Image = plain(width: 3, height: 2, space: displayP3, [1, 2, 3])
        #expect(StudioOutput(colors: .display).prepared(p3Image, pointScale: 2) === p3Image)
        let transparent = picture(width: 1, height: 1, space: displayP3, [[0, 0, 0, 0]])
        #expect(StudioOutput(format: .heic, colors: .display).prepared(transparent, pointScale: 1) === transparent)
    }

    @Test func sRGBConvertsADisplayP3Picture() throws {
        // sRGB red in Display P3 is about (234, 51, 35): converted, it is sRGB red again.
        let image = plain(width: 2, height: 2, space: displayP3, [35, 51, 234])
        let converted = try #require(StudioOutput().prepared(image, pointScale: 1))
        #expect(converted.colorSpace?.name == CGColorSpace.sRGB)
        #expect(pixels(converted, in: sRGB).allSatisfy { near($0, [0, 0, 255, 255], within: 2) })
    }

    @Test func displayKeepsTheDisplaysValues() throws {
        let image = plain(width: 2, height: 2, space: displayP3, [35, 51, 234])
        let kept = try #require(StudioOutput(colors: .display, scale: .points).prepared(image, pointScale: 2))
        #expect(kept.colorSpace?.name == CGColorSpace.displayP3)
        #expect(pixels(kept, in: displayP3) == [[35, 51, 234, 255]])
    }

    @Test func jpegLaysATransparentPictureOnWhite() throws {
        // Transparent, half-transparent red (premultiplied) and opaque blue.
        let image = picture(width: 3, height: 1, space: sRGB, [[0, 0, 0, 0], [0, 0, 128, 128], [255, 0, 0, 255]])
        let flat = try #require(StudioOutput(format: .jpeg).prepared(image, pointScale: 1))
        #expect(!StudioComposite.hasAlpha(flat))
        let result = pixels(flat, in: sRGB)
        #expect(result[0] == [255, 255, 255, 255])
        #expect(near(result[1], [127, 127, 255, 255], within: 1))
        #expect(result[2] == [255, 0, 0, 255])
    }

    @Test func pngAndHEICKeepTransparency() throws {
        let image = picture(width: 2, height: 1, space: displayP3, [[0, 0, 0, 0], [0, 0, 128, 128]])
        for format in [StudioOutput.Format.png, .heic] {
            let kept = try #require(StudioOutput(format: format).prepared(image, pointScale: 1))
            #expect(StudioComposite.hasAlpha(kept))
            #expect(pixels(kept, in: sRGB)[0] == [0, 0, 0, 0])
        }
    }
}

struct StudioOutputEncodingTests {
    /// 16 × 16 px: the left half transparent, the right half opaque, in `space` — large flat areas,
    /// so the lossy formats keep the colours close.
    private func halfTransparent(_ space: CGColorSpace, _ bgr: [UInt8]) -> CGImage {
        let clear: [UInt8] = [0, 0, 0, 0]
        let rows = (0..<16).flatMap { _ in (0..<16).map { x in x < 8 ? clear : bgr + [255] } }
        return picture(width: 16, height: 16, space: space, rows)
    }

    @Test func eachFormatRoundTripsItsSize() throws {
        let image = plain(width: 21, height: 13, space: sRGB, [10, 20, 30])
        for format in StudioOutput.Format.allCases {
            let decoded = try Decoded(try #require(StudioOutput.encoded(image, as: format)))
            #expect((decoded.image.width, decoded.image.height) == (21, 13), "\(format)")
        }
    }

    @Test func pngKeepsEveryPixelAndItsAlpha() throws {
        let image = halfTransparent(sRGB, [200, 100, 50])
        let decoded = try Decoded(try #require(StudioOutput.encoded(image, as: .png)))
        #expect(decoded.properties[kCGImagePropertyHasAlpha as String] as? Bool == true)
        #expect(pixels(decoded.image, in: sRGB) == pixels(image, in: sRGB))
    }

    @Test func heicKeepsAlpha() throws {
        let image = halfTransparent(sRGB, [200, 100, 50])
        let decoded = try Decoded(try #require(StudioOutput.encoded(image, as: .heic)))
        #expect(decoded.properties[kCGImagePropertyHasAlpha as String] as? Bool == true)
        #expect(StudioComposite.hasAlpha(decoded.image))
        let result = pixels(decoded.image, in: sRGB)
        #expect(result[16 * 4 + 2][3] == 0)
        #expect(near(result[16 * 4 + 12], [200, 100, 50, 255], within: 4))
    }

    @Test func jpegOfAPreparedPictureIsOpaqueAndWhiteWhereItWasTransparent() throws {
        let output = StudioOutput(format: .jpeg)
        let prepared = try #require(output.prepared(halfTransparent(sRGB, [200, 100, 50]), pointScale: 1))
        let decoded = try Decoded(try #require(StudioOutput.encoded(prepared, as: .jpeg)))
        #expect(decoded.properties[kCGImagePropertyHasAlpha as String] as? Bool != true)
        #expect(!StudioComposite.hasAlpha(decoded.image))
        let result = pixels(decoded.image, in: sRGB)
        #expect(near(result[16 * 4 + 2], [255, 255, 255, 255], within: 3))
        #expect(near(result[16 * 4 + 12], [200, 100, 50, 255], within: 4))
    }

    @Test func sRGBIsDeclaredInEveryFormat() throws {
        let image = plain(width: 8, height: 8, space: sRGB, [10, 20, 30])
        for format in StudioOutput.Format.allCases {
            let decoded = try Decoded(try #require(StudioOutput.encoded(image, as: format)))
            #expect(decoded.image.colorSpace?.name == CGColorSpace.sRGB, "\(format)")
            #expect(decoded.properties[kCGImagePropertyProfileName as String] as? String == "sRGB IEC61966-2.1")
        }
    }

    @Test func displayP3IsEmbeddedInEveryFormat() throws {
        let image = plain(width: 8, height: 8, space: displayP3, [35, 51, 234])
        for format in StudioOutput.Format.allCases {
            let decoded = try Decoded(try #require(StudioOutput.encoded(image, as: format)))
            #expect(decoded.image.colorSpace?.name == CGColorSpace.displayP3, "\(format)")
            #expect(decoded.properties[kCGImagePropertyProfileName as String] as? String == "Display P3")
            #expect(near(pixels(decoded.image, in: displayP3)[27], [35, 51, 234, 255], within: 4), "\(format)")
        }
    }

    @Test func everyFormatIsAt72DPI() throws {
        let image = plain(width: 8, height: 8, space: sRGB, [10, 20, 30])
        for format in StudioOutput.Format.allCases {
            let decoded = try Decoded(try #require(StudioOutput.encoded(image, as: format)))
            #expect(decoded.properties[kCGImagePropertyDPIWidth as String] as? Double == 72, "\(format)")
            #expect(decoded.properties[kCGImagePropertyDPIHeight as String] as? Double == 72, "\(format)")
        }
    }

    @Test func noFormatCarriesDatesDeviceSoftwareOrLocation() throws {
        let image = halfTransparent(displayP3, [200, 100, 50])
        // ImageIO's minimal Exif: the colour space and the pixel size, nothing else.
        let allowedExif: Set<String> = [
            kCGImagePropertyExifColorSpace, kCGImagePropertyExifPixelXDimension,
            kCGImagePropertyExifPixelYDimension,
        ].reduce(into: []) { $0.insert($1 as String) }
        let forbiddenTIFF = [
            kCGImagePropertyTIFFDateTime, kCGImagePropertyTIFFSoftware, kCGImagePropertyTIFFMake,
            kCGImagePropertyTIFFModel, kCGImagePropertyTIFFHostComputer, kCGImagePropertyTIFFArtist,
            kCGImagePropertyTIFFCopyright, kCGImagePropertyTIFFImageDescription,
        ].map { $0 as String }
        for format in StudioOutput.Format.allCases {
            let decoded = try Decoded(try #require(StudioOutput.encoded(image, as: format)))
            let exif = decoded.dictionary(kCGImagePropertyExifDictionary) ?? [:]
            #expect(Set(exif.keys).isSubset(of: allowedExif), "\(format): \(exif.keys.sorted())")
            let tiff = decoded.dictionary(kCGImagePropertyTIFFDictionary) ?? [:]
            #expect(forbiddenTIFF.allSatisfy { tiff[$0] == nil }, "\(format): \(tiff.keys.sorted())")
            for dictionary in [
                kCGImagePropertyGPSDictionary, kCGImagePropertyIPTCDictionary, kCGImagePropertyExifAuxDictionary,
                kCGImagePropertyMakerAppleDictionary,
            ] {
                #expect(decoded.dictionary(dictionary) == nil, "\(format): \(dictionary)")
            }
            let png = decoded.dictionary(kCGImagePropertyPNGDictionary) ?? [:]
            #expect(png[kCGImagePropertyPNGCreationTime as String] == nil)
            #expect(png[kCGImagePropertyPNGModificationTime as String] == nil)
            #expect(png[kCGImagePropertyPNGSoftware as String] == nil)
            let tags = decoded.tagPaths.map { $0.lowercased() }
            for word in ["date", "time", "software", "make", "model", "creator", "gps", "lens", "serial"] {
                #expect(!tags.contains { $0.contains(word) }, "\(format): \(decoded.tagPaths)")
            }
        }
    }

    @Test func aTransparentPictureOnATwoXDisplayAsJPEGInSRGBAtOneX() throws {
        // A lone window's picture: transparent around, opaque Display P3 red in the middle; large
        // enough that JPEG's colour blocks lie inside one or the other.
        let red: [UInt8] = [35, 51, 234, 255]
        let clear: [UInt8] = [0, 0, 0, 0]
        let rows = (0..<32).flatMap { y in
            (0..<32).map { x in (8..<24).contains(x) && (8..<24).contains(y) ? red : clear }
        }
        let image = picture(width: 32, height: 32, space: displayP3, rows)
        let output = StudioOutput(format: .jpeg, colors: .sRGB, scale: .points)
        let prepared = try #require(output.prepared(image, pointScale: 2))
        let decoded = try Decoded(try #require(StudioOutput.encoded(prepared, as: .jpeg)))
        #expect((decoded.image.width, decoded.image.height) == (16, 16))
        #expect(decoded.image.colorSpace?.name == CGColorSpace.sRGB)
        #expect(!StudioComposite.hasAlpha(decoded.image))
        let result = pixels(decoded.image, in: sRGB)
        #expect(near(result[0], [255, 255, 255, 255], within: 4))
        #expect(near(result[8 * 16 + 8], [0, 0, 255, 255], within: 4))
    }

    @Test func theClipboardHasTheFormatThenPNGThenTIFF() {
        #expect(StudioOutput.pasteboardTypes(for: .png) == ["public.png", "public.tiff"])
        #expect(StudioOutput.pasteboardTypes(for: .jpeg) == ["public.jpeg", "public.png", "public.tiff"])
        #expect(StudioOutput.pasteboardTypes(for: .heic) == ["public.heic", "public.png", "public.tiff"])
    }

    @Test func writtenGivesTheFileAndEachClipboardTypeFromOnePicture() throws {
        let image = halfTransparent(displayP3, [200, 100, 50])
        for format in StudioOutput.Format.allCases {
            let output = StudioOutput(format: format, colors: .sRGB, scale: .points)
            let written = try #require(output.written(image, pointScale: 2, forPasteboard: true))
            #expect((written.picture.width, written.picture.height) == (8, 8))
            #expect(written.data == StudioOutput.encoded(written.picture, as: format))
            #expect(written.pasteboard.map(\.type) == StudioOutput.pasteboardTypes(for: format))
            #expect(written.pasteboard.first?.data == written.data)
            for item in written.pasteboard {
                let decoded = try Decoded(item.data)
                #expect((decoded.image.width, decoded.image.height) == (8, 8), "\(format) \(item.type)")
                #expect(decoded.image.colorSpace?.name == CGColorSpace.sRGB, "\(format) \(item.type)")
                // Laid on white for JPEG, in every type; transparent otherwise.
                #expect(StudioComposite.hasAlpha(decoded.image) == format.keepsAlpha, "\(format) \(item.type)")
            }
        }
    }

    @Test func aPictureOnlySavedHasNoClipboardData() throws {
        let written = try #require(
            StudioOutput(format: .heic).written(halfTransparent(sRGB, [1, 2, 3]), pointScale: 2, forPasteboard: false))
        #expect(written.pasteboard.isEmpty)
    }
}

struct StudioOutputAlphaTests {
    /// `width` × `height` opaque pixels of many values, with alpha, as a capture of the screen gives
    /// them, in `space`; with `alpha` at each of `translucent` (column, row from the top).
    private func capture(
        width: Int = 8, height: Int = 6, space: CGColorSpace = sRGB, translucent: [(x: Int, y: Int)] = [],
        alpha: UInt8 = 0
    ) -> CGImage {
        var rows = (0..<(width * height)).map { index -> [UInt8] in
            [UInt8(index * 37 % 256), UInt8(index * 91 % 256), UInt8(255 - index * 13 % 256), 255]
        }
        // Premultiplied: a translucent pixel's colour is no more than its alpha.
        for point in translucent { rows[point.y * width + point.x] = [0, alpha / 2, alpha, alpha] }
        return picture(width: width, height: height, space: space, rows)
    }

    /// `image`'s pixels without alpha, as a context of its own space draws them.
    private func withoutAlpha(_ image: CGImage) -> CGImage {
        let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: image.colorSpace!,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()!
    }

    @Test func anOpaqueCaptureIsWrittenWithoutAlphaAndItsPixelsUnchanged() throws {
        for (space, colors) in [(sRGB, StudioOutput.Colors.sRGB), (displayP3, .display)] {
            let image = capture(space: space)
            for format in StudioOutput.Format.allCases {
                let prepared = try #require(StudioOutput(format: format, colors: colors).prepared(image, pointScale: 2))
                #expect(prepared !== image, "\(format) \(colors)")
                #expect(!StudioComposite.hasAlpha(prepared), "\(format) \(colors)")
                #expect(prepared.colorSpace == space, "\(format) \(colors)")
                #expect((prepared.width, prepared.height) == (8, 6), "\(format) \(colors)")
                #expect(pixels(prepared, in: space) == pixels(image, in: space), "\(format) \(colors)")
            }
        }
    }

    @Test func oneTranslucentPixelKeepsAlphaWhereTheFormatKeepsIt() throws {
        let (width, height) = (8, 6)
        let places = [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1), (3, 2)]
        for (x, y) in places {
            for alpha: UInt8 in [0, 1, 128, 254] {
                let image = capture(width: width, height: height, translucent: [(x, y)], alpha: alpha)
                for format in [StudioOutput.Format.png, .heic] {
                    let prepared = try #require(StudioOutput(format: format).prepared(image, pointScale: 2))
                    // Nothing else to change: the capture itself, every pixel exact.
                    #expect(prepared === image, "\(format) (\(x), \(y)) alpha \(alpha)")
                }
                let flat = try #require(StudioOutput(format: .jpeg).prepared(image, pointScale: 2))
                #expect(!StudioComposite.hasAlpha(flat), "(\(x), \(y)) alpha \(alpha)")
            }
        }
    }

    @Test func aTranslucentPictureConvertedOrScaledKeepsAlpha() throws {
        let image = capture(space: displayP3, translucent: [(7, 5)], alpha: 254)
        for format in [StudioOutput.Format.png, .heic] {
            let converted = try #require(StudioOutput(format: format).prepared(image, pointScale: 2))
            #expect(StudioComposite.hasAlpha(converted))
            #expect(pixels(converted, in: sRGB)[47][3] == 254)
            // Averaged with three opaque pixels, 254 would round back to 255: a transparent pixel.
            let clear = capture(space: displayP3, translucent: [(7, 5)], alpha: 0)
            let scaled = try #require(
                StudioOutput(format: format, colors: .display, scale: .points).prepared(clear, pointScale: 2))
            #expect(StudioComposite.hasAlpha(scaled))
            #expect((scaled.width, scaled.height) == (4, 3))
            // (255 × 3 + 0) / 4: about 191.
            #expect(near([pixels(scaled, in: displayP3)[11][3]], [191], within: 1))
        }
    }

    @Test func jpegOfAnOpaqueCaptureIsItsPixelsWithoutAlpha() throws {
        let image = capture()
        let flat = try #require(StudioOutput(format: .jpeg).prepared(image, pointScale: 1))
        #expect(!StudioComposite.hasAlpha(flat))
        #expect(pixels(flat, in: sRGB) == pixels(image, in: sRGB))
    }

    @Test func aPictureWithoutAlphaIsKeptAsItIsInEveryFormat() {
        let image = withoutAlpha(capture())
        for format in StudioOutput.Format.allCases {
            #expect(StudioOutput(format: format).prepared(image, pointScale: 2) === image, "\(format)")
        }
    }

    @Test func anOpaqueCaptureScaledToOneXHasNoAlpha() throws {
        // 2 × 2 blocks of red and blue, with alpha: each becomes one opaque pixel of its colour.
        let red: [UInt8] = [0, 0, 255, 255]
        let blue: [UInt8] = [255, 0, 0, 255]
        let rows = (0..<8).map { y in (0..<8).map { x in (x / 2 + y / 2).isMultiple(of: 2) ? red : blue } }
        let image = picture(width: 8, height: 8, space: sRGB, rows.flatMap { $0 })
        for format in [StudioOutput.Format.png, .heic] {
            let scaled = try #require(StudioOutput(format: format, scale: .points).prepared(image, pointScale: 2))
            #expect(!StudioComposite.hasAlpha(scaled), "\(format)")
            let expected = (0..<4).flatMap { y in (0..<4).map { x in (x + y).isMultiple(of: 2) ? red : blue } }
            #expect(pixels(scaled, in: sRGB) == expected, "\(format)")
        }
    }

    @Test func anOpaqueCaptureConvertedToSRGBHasNoAlphaAndTheSamePixelsAsWithoutIt() throws {
        let image = capture(space: displayP3)
        for format in [StudioOutput.Format.png, .heic] {
            let converted = try #require(StudioOutput(format: format).prepared(image, pointScale: 1))
            #expect(!StudioComposite.hasAlpha(converted), "\(format)")
            #expect(converted.colorSpace?.name == CGColorSpace.sRGB, "\(format)")
            let reference = try #require(StudioOutput(format: format).prepared(withoutAlpha(image), pointScale: 1))
            #expect(pixels(converted, in: sRGB) == pixels(reference, in: sRGB), "\(format)")
        }
    }

    @Test func anOpaqueCaptureIsEncodedWithoutAlphaInTheFileAndOnTheClipboard() throws {
        let image = capture(space: displayP3)
        for format in StudioOutput.Format.allCases {
            let output = StudioOutput(format: format, colors: .display)
            let written = try #require(output.written(image, pointScale: 2, forPasteboard: true))
            for item in [(type: format.typeIdentifier, data: written.data)] + written.pasteboard {
                let decoded = try Decoded(item.data)
                #expect(
                    decoded.properties[kCGImagePropertyHasAlpha as String] as? Bool != true, "\(format) \(item.type)")
                #expect(!StudioComposite.hasAlpha(decoded.image), "\(format) \(item.type)")
            }
        }
        let prepared = try #require(StudioOutput(colors: .display).prepared(image, pointScale: 1))
        let png = try Decoded(try #require(StudioOutput.encoded(prepared, as: .png)))
        #expect(pixels(png.image, in: displayP3) == pixels(image, in: displayP3))
    }

    @Test func aCaptureWithOneTranslucentPixelIsEncodedWithAlpha() throws {
        let image = capture(translucent: [(7, 5)], alpha: 254)
        for format in [StudioOutput.Format.png, .heic] {
            let written = try #require(StudioOutput(format: format).written(image, pointScale: 1, forPasteboard: true))
            for item in [(type: format.typeIdentifier, data: written.data)] + written.pasteboard {
                let decoded = try Decoded(item.data)
                #expect(
                    decoded.properties[kCGImagePropertyHasAlpha as String] as? Bool == true, "\(format) \(item.type)")
            }
        }
    }
}
