import CoreGraphics
import Foundation
import Testing

private let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
private let displayP3 = CGColorSpace(name: CGColorSpace.displayP3)!

/// Premultiplied BGRA pixels, as ScreenCaptureKit gives them: `pixels` row by row from the top,
/// each `[blue, green, red, alpha]`.
private func capture(width: Int, height: Int, space: CGColorSpace?, _ pixels: [[UInt8]]) -> CGImage {
    let bytes = pixels.flatMap { $0 }
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    return CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
        space: space ?? sRGB,
        bitmapInfo: CGBitmapInfo(
            rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
}

/// The pixels of `image` as `[blue, green, red, alpha]` from the top row, read in `space` with no
/// conversion when it is the image's own.
private func pixels(_ image: CGImage, in space: CGColorSpace) -> [[UInt8]] {
    let context = CGContext(
        data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let data = context.data!.assumingMemoryBound(to: UInt8.self)
    return (0..<(image.width * image.height)).map { index in
        (0..<4).map { data[index * 4 + $0] }
    }
}

private func near(_ a: UInt8, _ b: Int, within tolerance: Int = 1) -> Bool {
    abs(Int(a) - b) <= tolerance
}

struct StudioCompositeTests {
    // A 3 × 2 picture: opaque pixels of all kinds, one transparent, one half-transparent black,
    // premultiplied.
    private let picture: [[UInt8]] = [
        [10, 20, 30, 255], [0, 0, 255, 255], [0, 0, 0, 0],
        [255, 255, 255, 255], [0, 0, 0, 128], [7, 200, 99, 255],
    ]

    @Test func anImageInTheDisplaysSpaceIsKeptAsItIs() {
        let image = capture(width: 3, height: 2, space: displayP3, picture)
        let result = StudioComposite.composited(image, in: displayP3)
        #expect(result === image)
    }

    @Test func anUntaggedImageIsTaggedWithTheDisplaysSpaceUnchanged() {
        let image = capture(width: 3, height: 2, space: displayP3, picture).copy(colorSpace: sRGB)!
        let result = StudioComposite.composited(image, in: sRGB)!
        #expect(result.colorSpace == sRGB)
        #expect(pixels(result, in: sRGB)[0] == picture[0])
    }

    @Test func anImageInAnotherSpaceIsConvertedIntoTheDisplays() {
        let image = capture(width: 1, height: 1, space: sRGB, [[0, 0, 255, 255]])
        let result = StudioComposite.composited(image, in: displayP3)!
        #expect(result.colorSpace == displayP3)
        // sRGB red in Display P3 is about (234, 51, 35).
        let pixel = pixels(result, in: displayP3)[0]
        #expect(near(pixel[2], 234, within: 2) && near(pixel[1], 51, within: 3) && near(pixel[0], 35, within: 3))
    }

    @Test func aConvertedPictureIsCopiedWithoutInterpolation() {
        // A checkerboard of single pixels would blur under any resampling; black and white stay
        // themselves in any space.
        let width = 64
        let height = 40
        let board = (0..<(width * height)).map { index -> [UInt8] in
            (index % width + index / width) % 2 == 0 ? [0, 0, 0, 255] : [255, 255, 255, 255]
        }
        let image = capture(width: width, height: height, space: sRGB, board)
        let result = StudioComposite.composited(image, in: displayP3)!
        #expect(result.width == width && result.height == height)
        #expect(pixels(result, in: displayP3) == board)
    }

    // MARK: The backdrop's picture

    @Test func aColourFillsTheWholeBackdrop() {
        let size = PixelSize(width: 7, height: 5)
        let result = StudioComposite.filled(.color(BackgroundColor(0, 128, 255)), size: size, space: sRGB)!
        #expect(result.width == 7 && result.height == 5)
        #expect(result.colorSpace == sRGB)
        #expect(pixels(result, in: sRGB).allSatisfy { $0 == [255, 128, 0, 255] })
    }

    @Test func theBackdropIsOpaque() {
        let result = StudioComposite.filled(.color(.black), size: PixelSize(width: 3, height: 2), space: sRGB)!
        #expect(!StudioComposite.hasAlpha(result))
        #expect(pixels(result, in: sRGB).allSatisfy { $0 == [0, 0, 0, 255] })
    }

    @Test func anEmptyBackdropIsNone() {
        #expect(StudioComposite.filled(.color(.white), size: PixelSize(width: 0, height: 10), space: sRGB) == nil)
        #expect(StudioComposite.filled(.color(.white), size: PixelSize(width: 10, height: 0), space: sRGB) == nil)
    }

    /// White is 255, 255, 255 in the display's space whichever it is, so the picture of a white
    /// backdrop is exactly white.
    @Test func whiteStaysExactlyWhiteInAnyDisplaysSpace() {
        let spaces = [
            sRGB, displayP3, CGColorSpace(name: CGColorSpace.adobeRGB1998)!,
            CGColorSpace(name: CGColorSpace.genericRGBLinear)!,
        ]
        for space in spaces {
            let result = StudioComposite.filled(.color(.white), size: PixelSize(width: 2, height: 2), space: space)!
            #expect(
                pixels(result, in: space).allSatisfy { $0 == [255, 255, 255, 255] }, "\(String(describing: space.name))"
            )
            let black = StudioComposite.filled(.color(.black), size: PixelSize(width: 2, height: 2), space: space)!
            #expect(pixels(black, in: space).allSatisfy { $0 == [0, 0, 0, 255] }, "\(String(describing: space.name))")
        }
    }

    @Test func anSRGBColourIsColourMatchedIntoAP3Display() {
        let red = BackgroundColor(255, 0, 0)
        let result = StudioComposite.filled(.color(red), size: PixelSize(width: 1, height: 1), space: displayP3)!
        let pixel = pixels(result, in: displayP3)[0]
        #expect(near(pixel[2], 234, within: 2) && near(pixel[1], 51, within: 3) && near(pixel[0], 35, within: 3))
    }

    /// The backdrop's colour is the same pixels One Window lays under its window: both draw with
    /// `StudioFill.draw`.
    @Test func theBackdropsColourMatchesOneWindowsBackground() {
        let colour = BackgroundColor(70, 82, 140)
        let window = capture(width: 1, height: 1, space: displayP3, [[0, 0, 0, 0]])
        let lone = StudioComposite.centred(
            window, in: PixelSize(width: 3, height: 3), space: displayP3, over: .color(colour))!
        let backdrop = StudioComposite.filled(.color(colour), size: PixelSize(width: 3, height: 3), space: displayP3)!
        #expect(pixels(lone, in: displayP3)[0] == pixels(backdrop, in: displayP3)[0])
    }

    @Test func aGradientRunsFromTheTopColourToTheBottomOne() {
        let height = 101
        let gradient = BackgroundGradient(top: .black, bottom: .white)
        let out = pixels(
            StudioComposite.filled(.gradient(gradient), size: PixelSize(width: 3, height: height), space: sRGB)!,
            in: sRGB)
        #expect(out[0][0] <= 3)
        #expect(out[out.count - 1][0] >= 252)
        #expect(near(out[(height / 2) * 3][0], 128, within: 4))
        // Getting lighter all the way down. CoreGraphics dithers a gradient, so a row may vary by a
        // step across.
        let column = stride(from: 0, to: out.count, by: 3).map { out[$0] }
        #expect(zip(column, column.dropFirst()).allSatisfy { $0[0] <= $1[0] + 1 })
        #expect((0..<height).allSatisfy { row in near(out[row * 3][0], Int(out[row * 3 + 2][0])) })
    }

    @Test func aBackgroundImageWithAlphaIsLaidOnWhite() {
        let clear = capture(width: 2, height: 2, space: sRGB, Array(repeating: [0, 0, 0, 0], count: 4))
        let out = pixels(
            StudioComposite.filled(.image(clear), size: PixelSize(width: 3, height: 3), space: sRGB)!, in: sRGB)
        #expect(out.allSatisfy { $0 == [255, 255, 255, 255] })
    }

    @Test func aBackgroundImageCoversTheBackdrop() {
        // A 1 × 2 image, red over blue, under a 4 × 8 backdrop: scaled by 4 to cover it exactly,
        // red in the top rows and blue in the bottom rows, blended only around the middle.
        let image = capture(width: 1, height: 2, space: sRGB, [[0, 0, 255, 255], [255, 0, 0, 255]])
        let out = pixels(
            StudioComposite.filled(.image(image), size: PixelSize(width: 4, height: 8), space: sRGB)!, in: sRGB)
        #expect(out.allSatisfy { $0[3] == 255 })
        #expect(out[0][2] > 200 && out[0][0] < 60)
        #expect(out[31][0] > 200 && out[31][2] < 60)
    }

    @Test func aWiderImageIsCutAtTheBackdropsSides() {
        // 5 × 1: red, three greens, blue, under a 2 × 2 backdrop: scaled by 2 to 10 × 2, 4 cut on
        // each side, so only the green middle shows.
        let green: [UInt8] = [0, 255, 0, 255]
        let image = capture(
            width: 5, height: 1, space: sRGB, [[0, 0, 255, 255], green, green, green, [255, 0, 0, 255]])
        let out = pixels(
            StudioComposite.filled(.image(image), size: PixelSize(width: 2, height: 2), space: sRGB)!, in: sRGB)
        #expect(out.allSatisfy { $0[1] > 200 && $0[0] < 60 && $0[2] < 60 })
    }

    // MARK: Alpha

    @Test func alphaIsToldApartFromSkippedBytes() {
        #expect(StudioComposite.hasAlpha(capture(width: 1, height: 1, space: sRGB, [[0, 0, 0, 0]])))
        let context = CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: sRGB,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        #expect(!StudioComposite.hasAlpha(context.makeImage()!))
    }

    // MARK: Background image size

    @Test func aLargeImageIsDecodedJustLargeEnoughToCover() {
        // 6000 × 4000 under 2880 × 1800: covering takes 0.48, so 2880 × 1920.
        #expect(
            StudioComposite.backgroundMaxPixelSize(
                image: PixelSize(width: 6000, height: 4000), display: PixelSize(width: 2880, height: 1800)) == 2880)
        // A panorama keeps its height: 12000 × 1000 under 2880 × 1800 would be scaled up, so whole.
        #expect(
            StudioComposite.backgroundMaxPixelSize(
                image: PixelSize(width: 12000, height: 1000), display: PixelSize(width: 2880, height: 1800)) == 12000)
        // A tall one: 3000 × 9000 under 1920 × 1080 takes 0.64, so 5760 on its long side.
        #expect(
            StudioComposite.backgroundMaxPixelSize(
                image: PixelSize(width: 3000, height: 9000), display: PixelSize(width: 1920, height: 1080)) == 5760)
    }

    @Test func aSmallImageIsNeverScaledUp() {
        #expect(
            StudioComposite.backgroundMaxPixelSize(
                image: PixelSize(width: 800, height: 600), display: PixelSize(width: 5120, height: 2880)) == 800)
        #expect(
            StudioComposite.backgroundMaxPixelSize(
                image: PixelSize(width: 2880, height: 1800), display: PixelSize(width: 2880, height: 1800)) == 2880)
    }

    @Test func aFractionalCoverRoundsUpSoItStillCovers() {
        // 3001 × 3001 under 1000 × 1000: 1000.0 exactly; 3000 × 2999 under 1000 × 1000: 1000.33…, so 1001.
        #expect(
            StudioComposite.backgroundMaxPixelSize(
                image: PixelSize(width: 3001, height: 3001), display: PixelSize(width: 1000, height: 1000)) == 1000)
        #expect(
            StudioComposite.backgroundMaxPixelSize(
                image: PixelSize(width: 3000, height: 2999), display: PixelSize(width: 1000, height: 1000)) == 1001)
    }

    @Test func anEmptyImageOrNoDisplayStaysAtLeastOnePixel() {
        #expect(
            StudioComposite.backgroundMaxPixelSize(
                image: PixelSize(width: 0, height: 0), display: PixelSize(width: 1920, height: 1080)) == 1)
        #expect(
            StudioComposite.backgroundMaxPixelSize(
                image: PixelSize(width: 4000, height: 3000), display: PixelSize(width: 0, height: 0)) == 1)
    }

    @Test func theLargestPictureTakesTheWidestAndTallestDisplaysInPixels() {
        let displays = [
            DisplayInfo(id: 1, globalFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2),
            DisplayInfo(id: 2, globalFrame: CGRect(x: -1920, y: -200, width: 1920, height: 1200), scale: 1),
            DisplayInfo(id: 3, globalFrame: CGRect(x: 1440, y: 900, width: 1080, height: 1920), scale: 1),
        ]
        #expect(StudioComposite.largestPicture(on: displays) == PixelSize(width: 2880, height: 1920))
        #expect(StudioComposite.largestPicture(on: []) == PixelSize(width: 0, height: 0))
    }
}
