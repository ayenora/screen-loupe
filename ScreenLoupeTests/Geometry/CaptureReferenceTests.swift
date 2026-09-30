import CoreGraphics
import Foundation
import ImageIO
import Testing

struct CaptureReferenceLayerTests {
    private let utc = TimeZone(identifier: "UTC")!
    /// 2026-07-12 14:32:05 UTC.
    private let date = Date(timeIntervalSince1970: 1_783_866_725)
    private let id = UUID()

    private func layer(
        _ source: CaptureReference.Source, _ layout: FrameLayout, at pictureOrigin: CGPoint = .zero
    ) -> ReferenceLayer {
        CaptureReference.layer(
            source, layout: layout, pictureOrigin: pictureOrigin, id: id, fileName: "pixels.tiff", timeZone: utc)
    }

    private let whole = FrameLayout(image: PixelSize(width: 294, height: 240))

    // MARK: Where it lands

    @Test func aSnapshotLandsWhereItWasInTheCaptureArea() {
        let made = layer(.snapshot(date: date), whole, at: CGPoint(x: 100, y: 50))
        #expect(made.origin == CGPoint(x: 100, y: 50))
        #expect(made.frame == CGRect(x: 100, y: 50, width: 294, height: 240))
    }

    @Test func aSnapshotOfTheWholeAreaLandsOnIt() {
        #expect(layer(.snapshot(date: date), whole).origin == .zero)
    }

    @Test func anImageLandsAtTheTopLeftAsAddDoes() {
        #expect(layer(.image(name: "photo.png"), whole).origin == .zero)
    }

    @Test func theFrozenFrameCoversTheCaptureArea() {
        let made = layer(.frozenFrame(date: date), whole)
        #expect(made.frame == CGRect(x: 0, y: 0, width: 294, height: 240))
    }

    /// An area straddling two displays: the frame's pixels start inside the picture, and so does
    /// the layer, on the pixels they were taken from.
    @Test func theFramesOffsetInThePictureMovesItToo() {
        let straddling = FrameLayout(
            size: PixelSize(width: 300, height: 200), imageOrigin: CGPoint(x: 40, y: 0),
            imageSize: PixelSize(width: 260, height: 200), scale: 2)
        #expect(layer(.frozenFrame(date: date), straddling).frame == CGRect(x: 40, y: 0, width: 260, height: 200))
        #expect(
            layer(.snapshot(date: date), straddling, at: CGPoint(x: 10, y: 20)).frame
                == CGRect(x: 50, y: 20, width: 260, height: 200))
    }

    // MARK: How it shows

    @Test(
        arguments: [
            CaptureReference.Source.snapshot(date: Date(timeIntervalSince1970: 0)), .image(name: "Pasted image"),
            .frozenFrame(date: Date(timeIntervalSince1970: 0)),
        ])
    func itShowsInDifferenceAtFullOpacityOnePixelToOne(source: CaptureReference.Source) {
        let made = layer(source, whole)
        #expect(made.blend == .difference)
        #expect(made.opacity == 1)
        #expect(made.scale == 1)
        #expect(made.imageSize == CGSize(width: 294, height: 240))
        #expect(made.isVisible)
        #expect(!made.isPinned)
        #expect(made.id == id)
        #expect(made.fileName == "pixels.tiff")
    }

    /// The Retina scale doesn't enter: a reference counts source pixels, as the capture does.
    @Test func aRetinaCaptureStaysOnePixelToOne() {
        let retina = FrameLayout(
            size: PixelSize(width: 588, height: 480), imageOrigin: .zero,
            imageSize: PixelSize(width: 588, height: 480), scale: 2)
        let made = layer(.frozenFrame(date: date), retina)
        #expect(made.scale == 1)
        #expect(made.frame.size == CGSize(width: 588, height: 480))
    }

    /// Past the image budget only the top-left part is kept, as for any added image.
    @Test func aPictureOverTheBudgetKeepsItsTopLeftPart() {
        let big = FrameLayout(image: PixelSize(width: 6016, height: 3384))
        let made = layer(.frozenFrame(date: date), big)
        let kept = ImageBudget.fitted(width: 6016, height: 3384)
        #expect(made.imageSize == CGSize(width: kept.width, height: kept.height))
        #expect(made.origin == .zero)
    }

    @Test func itGoesOnTopSelected() {
        var stack = ReferenceStack()
        stack.add(ReferenceLayer(name: "design.png", fileName: "a.png", imageSize: CGSize(width: 10, height: 10)))
        let made = layer(.frozenFrame(date: date), whole)
        #expect(stack.add(made) == true)
        #expect(stack.layers.first?.id == made.id)
        #expect(stack.selectedID == made.id)
    }

    @Test func aFullStackTakesNoMore() {
        var stack = ReferenceStack()
        for index in 0..<ReferenceStack.limit {
            stack.add(
                ReferenceLayer(name: "\(index)", fileName: "\(index).png", imageSize: CGSize(width: 1, height: 1)))
        }
        #expect(stack.add(layer(.frozenFrame(date: date), whole)) == false)
        #expect(stack.layers.count == ReferenceStack.limit)
    }

    // MARK: Its name

    @Test func aSnapshotIsNamedWithItsTime() {
        #expect(CaptureReference.name(.snapshot(date: date), timeZone: utc) == "Snapshot 14:32:05")
        #expect(layer(.snapshot(date: date), whole).name == "Snapshot 14:32:05")
    }

    @Test func anImageKeepsItsName() {
        #expect(CaptureReference.name(.image(name: "photo.png"), timeZone: utc) == "photo.png")
        #expect(CaptureReference.name(.image(name: "Pasted image"), timeZone: utc) == "Pasted image")
    }

    @Test func theFrozenFrameIsNamedWithTheTimeItFroze() {
        #expect(CaptureReference.name(.frozenFrame(date: date), timeZone: utc) == "Frozen frame 14:32:05")
    }

    @Test func theTimeIsInTwentyFourHoursInTheTimeZone() {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        #expect(CaptureReference.name(.frozenFrame(date: date), timeZone: tokyo) == "Frozen frame 23:32:05")
        let midnight = Date(timeIntervalSince1970: 1_783_814_400 + 5)
        #expect(CaptureReference.name(.snapshot(date: midnight), timeZone: utc) == "Snapshot 00:00:05")
    }
}

struct CaptureReferencePixelTests {
    /// The TIFF of `bytes` read back: its image and its pixels as straight BGRA.
    private func roundTrip(
        _ bytes: [UInt8], width: Int, height: Int, space: CGColorSpace, hasAlpha: Bool
    ) -> (image: CGImage, pixels: [UInt8])? {
        let tiff = bytes.withUnsafeBytes {
            CaptureReference.tiffData(
                bgra: $0.baseAddress!, width: width, height: height, bytesPerRow: width * 4, space: space,
                hasAlpha: hasAlpha)
        }
        guard let tiff, let source = CGImageSourceCreateWithData(tiff as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil), image.width == width, image.height == height
        else { return nil }
        var out = [UInt8](repeating: 0, count: width * 4 * height)
        let copied = out.withUnsafeMutableBytes {
            RecentCaptureArchive.copyPixels(of: image, into: $0.baseAddress!, bytesPerRow: width * 4)
        }
        return copied ? (image, out) : nil
    }

    /// Opaque pixels, every colour byte different from its neighbours.
    private func opaque(width: Int, height: Int) -> [UInt8] {
        (0..<width * height * 4).map { $0 % 4 == 3 ? 255 : UInt8(truncatingIfNeeded: $0 &* 131 &+ 7) }
    }

    /// A display's own profile, without a name: the TIFF keeps it byte for byte, so the layer is
    /// drawn into the display's space without a conversion and unchanged pixels match exactly.
    @Test func aDisplaysProfileIsKeptExactly() throws {
        let calibrated = try #require(
            CGColorSpace(
                calibratedRGBWhitePoint: [0.9505, 1, 1.089], blackPoint: [0, 0, 0], gamma: [2.2, 2.2, 2.2],
                matrix: [0.4124, 0.2126, 0.0193, 0.3576, 0.7152, 0.1192, 0.1805, 0.0722, 0.9505]))
        let profile = try #require(calibrated.copyICCData())
        let space = try #require(CGColorSpace(iccData: profile))
        let bytes = opaque(width: 16, height: 16)
        let back = try #require(roundTrip(bytes, width: 16, height: 16, space: space, hasAlpha: false))
        #expect(back.image.colorSpace?.copyICCData() == profile)
        #expect(back.pixels == bytes)
    }

    @Test(arguments: [CGColorSpace.sRGB, CGColorSpace.displayP3, CGColorSpace.adobeRGB1998] as [String])
    func aNamedSpaceComesBackWithEveryByte(spaceName: String) throws {
        let space = try #require(CGColorSpace(name: spaceName as CFString))
        let bytes = opaque(width: 37, height: 5)
        let back = try #require(roundTrip(bytes, width: 37, height: 5, space: space, hasAlpha: false))
        #expect(back.image.colorSpace?.name == space.name)
        #expect(back.pixels == bytes)
    }

    /// A frame of the screen is opaque whatever its alpha bytes hold.
    @Test func aFrameOfTheScreenIsOpaque() throws {
        let space = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let bytes: [UInt8] = [10, 20, 30, 0, 200, 100, 50, 7]
        let back = try #require(roundTrip(bytes, width: 2, height: 1, space: space, hasAlpha: false))
        #expect(back.pixels == [10, 20, 30, 255, 200, 100, 50, 255])
    }

    /// An image's transparency stays: fully transparent and opaque pixels as they were, and the
    /// opacity of the ones between.
    @Test func anImagesTransparencyIsKept() throws {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let bytes: [UInt8] = [10, 20, 30, 0, 200, 100, 50, 255, 0, 0, 255, 128]
        let back = try #require(roundTrip(bytes, width: 3, height: 1, space: space, hasAlpha: true))
        #expect(back.pixels[3] == 0)
        #expect(Array(back.pixels[4..<8]) == [200, 100, 50, 255])
        #expect(back.pixels[11] == 128)
    }

    /// Drawn premultiplied into the Viewer's space, as the renderer draws a layer, a transparent
    /// image's TIFF gives the very bytes its pixels give drawn directly: Difference treats it as it
    /// treats the image added with Add….
    @Test func aTransparentImageDrawsAsItsOwnPixelsDo() throws {
        let space = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let (width, height) = (64, 4)
        let bytes = (0..<width * height * 4).map { UInt8(truncatingIfNeeded: $0 &* 197 &+ 31) }
        let back = try #require(roundTrip(bytes, width: width, height: height, space: space, hasAlpha: true))
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        let straight = CGBitmapInfo(
            rawValue: CGImageAlphaInfo.first.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        let original = try #require(
            CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: space, bitmapInfo: straight, provider: provider, decode: nil, shouldInterpolate: false,
                intent: .defaultIntent))
        #expect(premultiplied(back.image, in: space) == premultiplied(original, in: space))
    }

    /// `image` drawn into premultiplied BGRA in `space`, as the renderer makes a layer's texture.
    private func premultiplied(_ image: CGImage, in space: CGColorSpace) -> [UInt8]? {
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard
            let context = CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: space, bitmapInfo: info),
            let data = context.data
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Array(UnsafeRawBufferPointer(start: data, count: image.width * 4 * image.height))
    }

    /// Rows padded as a pixel buffer's are: only each row's pixels are written.
    @Test func paddedRowsAreRead() throws {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let (width, height, bytesPerRow) = (3, 2, 16)
        var bytes = [UInt8](repeating: 99, count: bytesPerRow * height)
        let row0: [UInt8] = [1, 2, 3, 255, 4, 5, 6, 255, 7, 8, 9, 255]
        let row1: [UInt8] = [11, 12, 13, 255, 14, 15, 16, 255, 17, 18, 19, 255]
        bytes.replaceSubrange(0..<12, with: row0)
        bytes.replaceSubrange(16..<28, with: row1)
        let tiff = try #require(
            bytes.withUnsafeBytes {
                CaptureReference.tiffData(
                    bgra: $0.baseAddress!, width: width, height: height, bytesPerRow: bytesPerRow, space: space,
                    hasAlpha: false)
            })
        let source = try #require(CGImageSourceCreateWithData(tiff as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var out = [UInt8](repeating: 0, count: width * 4 * height)
        let copied = out.withUnsafeMutableBytes {
            RecentCaptureArchive.copyPixels(of: image, into: $0.baseAddress!, bytesPerRow: width * 4)
        }
        #expect(copied)
        #expect(out == row0 + row1)
    }
}
