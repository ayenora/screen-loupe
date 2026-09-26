import CoreGraphics
import Foundation
import Testing

private let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
private let displayP3 = CGColorSpace(name: CGColorSpace.displayP3)!

/// Premultiplied BGRA pixels, as ScreenCaptureKit gives them: `pixels` row by row from the top,
/// each `[blue, green, red, alpha]`.
private func capture(width: Int, height: Int, space: CGColorSpace = displayP3, _ pixels: [[UInt8]]) -> CGImage {
    let provider = CGDataProvider(data: Data(pixels.flatMap { $0 }) as CFData)!
    return CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: space,
        bitmapInfo: CGBitmapInfo(
            rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
}

/// A `width` × `height` capture, transparent but for `set`, keyed by (x, y) from the top-left.
private func capture(width: Int, height: Int, _ set: [Pixel: [UInt8]]) -> CGImage {
    capture(
        width: width, height: height,
        (0..<(width * height)).map { set[Pixel(x: $0 % width, y: $0 / width)] ?? [0, 0, 0, 0] })
}

private struct Pixel: Hashable {
    var x: Int
    var y: Int
}

/// The pixels of `image` as `[blue, green, red, alpha]` from the top row, read in `space`.
private func pixels(_ image: CGImage, in space: CGColorSpace = displayP3) -> [[UInt8]] {
    let context = CGContext(
        data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let data = context.data!.assumingMemoryBound(to: UInt8.self)
    return (0..<(image.width * image.height)).map { index in (0..<4).map { data[index * 4 + $0] } }
}

private let safari = OneWindowChoice(id: 42, appName: "Safari")
private let notes = OneWindowChoice(id: 7, appName: "Notes")

struct OneWindowModeTests {
    @Test func turningOnStartsPickingOnlyWhileTheStudioShows() {
        #expect(OneWindowMode.off.after(.toggle(studioVisible: true)) == .picking)
        #expect(OneWindowMode.off.after(.toggle(studioVisible: false)) == .off)
    }

    @Test func aClickOnAWindowChoosesIt() {
        #expect(OneWindowMode.picking.after(.picked(safari)) == .on(safari))
    }

    @Test func cancellingTheTogglePickerOrHidingEndsPicking() {
        #expect(OneWindowMode.picking.after(.cancelled) == .off)
        #expect(OneWindowMode.picking.after(.toggle(studioVisible: true)) == .off)
        #expect(OneWindowMode.picking.after(.hidden) == .off)
    }

    @Test func aWindowCheckWhilePickingChangesNothing() {
        #expect(OneWindowMode.picking.after(.checked(existing: [])) == .picking)
    }

    @Test func toggleTurnsAChosenWindowOff() {
        #expect(OneWindowMode.on(safari).after(.toggle(studioVisible: true)) == .off)
        #expect(OneWindowMode.on(safari).after(.toggle(studioVisible: false)) == .off)
    }

    @Test func hidingKeepsTheChosenWindow() {
        #expect(OneWindowMode.on(safari).after(.hidden) == .on(safari))
    }

    @Test func theChosenWindowClosingTurnsItOff() {
        #expect(OneWindowMode.on(safari).after(.checked(existing: [1, 42, 99])) == .on(safari))
        #expect(OneWindowMode.on(safari).after(.checked(existing: [1, 7, 99])) == .off)
        #expect(OneWindowMode.on(safari).after(.checked(existing: [])) == .off)
    }

    @Test func eventsThatDontApplyLeaveTheModeAsItIs() {
        #expect(OneWindowMode.on(safari).after(.picked(notes)) == .on(safari))
        #expect(OneWindowMode.on(safari).after(.cancelled) == .on(safari))
        #expect(OneWindowMode.off.after(.picked(safari)) == .off)
        #expect(OneWindowMode.off.after(.cancelled) == .off)
        #expect(OneWindowMode.off.after(.hidden) == .off)
        #expect(OneWindowMode.off.after(.checked(existing: [])) == .off)
    }

    @Test func aSessionChooseHideShowAndGone() {
        var mode = OneWindowMode.off
        for (event, expected) in [
            (OneWindowMode.Event.toggle(studioVisible: true), OneWindowMode.picking),
            (.picked(safari), .on(safari)),
            (.hidden, .on(safari)),
            // Shown again: the window is still there.
            (.checked(existing: [42]), .on(safari)),
            (.checked(existing: [43]), .off),
            (.toggle(studioVisible: true), .picking),
            (.picked(notes), .on(notes)),
        ] {
            mode = mode.after(event)
            #expect(mode == expected)
        }
    }

    @Test func theTabNamesTheChosenWindowsApp() {
        #expect(OneWindowMode.on(safari).tabNote == "One window: Safari")
        #expect(OneWindowMode.off.tabNote == nil)
        #expect(OneWindowMode.picking.tabNote == nil)
        #expect(OneWindowMode.on(safari).chosen == safari)
        #expect(OneWindowMode.picking.isPicking)
        #expect(!OneWindowMode.on(safari).isPicking)
    }
}

struct OneWindowPictureTests {
    // MARK: Fitting

    @Test func aPictureAsLargeAsTheFrameFits() {
        let frame = PixelSize(width: 2880, height: 1800)
        #expect(OneWindowPicture.fits(PixelSize(width: 2880, height: 1800), in: frame))
        #expect(OneWindowPicture.fits(PixelSize(width: 1, height: 1), in: frame))
    }

    @Test func onePixelOverInEitherAxisDoesntFit() {
        let frame = PixelSize(width: 2880, height: 1800)
        #expect(!OneWindowPicture.fits(PixelSize(width: 2881, height: 1800), in: frame))
        #expect(!OneWindowPicture.fits(PixelSize(width: 2880, height: 1801), in: frame))
        #expect(!OneWindowPicture.fits(PixelSize(width: 2881, height: 1801), in: frame))
        // Narrower but taller.
        #expect(!OneWindowPicture.fits(PixelSize(width: 100, height: 1801), in: frame))
    }

    @Test func theCaptureHasRoomOnEverySide() {
        #expect(
            OneWindowPicture.captureSize(frame: PixelSize(width: 1440, height: 900))
                == PixelSize(width: 1440 + 128, height: 900 + 128))
    }

    // MARK: Centring

    @Test func anEvenDifferenceCentresExactly() {
        let origin = OneWindowPicture.centredOrigin(
            of: PixelSize(width: 1600, height: 1000), in: PixelSize(width: 2880, height: 1800))
        #expect(origin == (640, 400))
    }

    @Test func anOddDifferenceLeavesTheExtraPixelRightAndBelow() {
        // 2880 − 1601 = 1279: 639 left, 640 right. 1800 − 1001 = 799: 399 above, 400 below.
        let origin = OneWindowPicture.centredOrigin(
            of: PixelSize(width: 1601, height: 1001), in: PixelSize(width: 2880, height: 1800))
        #expect(origin == (639, 399))
        // An odd frame at 1×, an even window.
        #expect(
            OneWindowPicture.centredOrigin(of: PixelSize(width: 2, height: 2), in: PixelSize(width: 5, height: 3))
                == (1, 0))
    }

    @Test func aPictureAsLargeAsTheFrameStartsAtItsCorner() {
        let size = PixelSize(width: 1441, height: 901)
        #expect(OneWindowPicture.centredOrigin(of: size, in: size) == (0, 0))
    }

    @Test func centringIsTheSameAtEveryScale() {
        // A 800 × 500 pt window with a 1 px wider shadow on each side, on a 1440 × 900 pt frame:
        // at 1× 802 × 502 px in 1440 × 900 px, at 2× 1602 × 1002 px in 2880 × 1800 px.
        #expect(
            OneWindowPicture.centredOrigin(
                of: PixelSize(width: 802, height: 502), in: PixelSize(width: 1440, height: 900))
                == (319, 199))
        #expect(
            OneWindowPicture.centredOrigin(
                of: PixelSize(width: 1602, height: 1002), in: PixelSize(width: 2880, height: 1800)) == (639, 399))
    }

    // MARK: Visible bounds

    @Test func theBoundsHoldEveryPixelThatIsntWhollyTransparent() {
        // A window's pixel and a faint shadow pixel (alpha 1) far from it, in a 6 × 5 capture.
        let image = capture(
            width: 6, height: 5, [Pixel(x: 1, y: 3): [9, 9, 9, 255], Pixel(x: 4, y: 1): [0, 0, 0, 1]])
        #expect(OneWindowPicture.visibleBounds(of: image) == PixelRect(x: 1, y: 1, width: 4, height: 3))
    }

    @Test func theBoundsCountFromTheTopLeft() {
        let image = capture(width: 4, height: 3, [Pixel(x: 3, y: 0): [1, 2, 3, 255]])
        #expect(OneWindowPicture.visibleBounds(of: image) == PixelRect(x: 3, y: 0, width: 1, height: 1))
        let bottom = capture(width: 4, height: 3, [Pixel(x: 0, y: 2): [1, 2, 3, 255]])
        #expect(OneWindowPicture.visibleBounds(of: bottom) == PixelRect(x: 0, y: 2, width: 1, height: 1))
    }

    @Test func aWhollyTransparentCaptureHasNoBounds() {
        #expect(OneWindowPicture.visibleBounds(of: capture(width: 3, height: 3, [:])) == nil)
    }

    @Test func aCaptureWithoutAlphaIsVisibleThroughout() {
        let context = CGContext(
            data: nil, width: 5, height: 4, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        #expect(
            OneWindowPicture.visibleBounds(of: context.makeImage()!) == PixelRect(x: 0, y: 0, width: 5, height: 4))
    }

    // MARK: Compositing

    /// A 2 × 2 window: two opaque pixels, a half-transparent shadow pixel and a clear corner.
    private let window: [[UInt8]] = [
        [10, 20, 30, 255], [0, 0, 0, 128],
        [7, 200, 99, 255], [0, 0, 0, 0],
    ]

    @Test func onTheScreenBackgroundTheRestIsTransparentAndTheWindowExact() {
        let image = capture(width: 2, height: 2, window)
        let result = StudioComposite.centred(image, in: PixelSize(width: 5, height: 4), space: displayP3, over: nil)!
        #expect(result.width == 5 && result.height == 4)
        #expect(StudioComposite.hasAlpha(result))
        #expect(result.colorSpace == displayP3)
        let out = pixels(result)
        // Origin (1, 1): the odd column goes right.
        for y in 0..<4 {
            for x in 0..<5 {
                let inside = (1...2).contains(x) && (1...2).contains(y)
                let expected = inside ? window[(y - 1) * 2 + (x - 1)] : [0, 0, 0, 0]
                #expect(out[y * 5 + x] == expected, "pixel (\(x), \(y))")
            }
        }
    }

    @Test func overAColourTheResultIsOpaqueAndTheShadowBlends() {
        let image = capture(width: 2, height: 2, space: sRGB, window)
        let result = StudioComposite.centred(
            image, in: PixelSize(width: 4, height: 3), space: sRGB, over: .color(.white))!
        #expect(!StudioComposite.hasAlpha(result))
        let out = pixels(result, in: sRGB)
        #expect(out.allSatisfy { $0[3] == 255 })
        // Origin (1, 0): the odd row goes below.
        #expect(out[1] == window[0])
        #expect(out[4 + 1] == window[2])
        // Black at 128/255 over white.
        #expect(out[2][0...2].allSatisfy { abs(Int($0) - 127) <= 1 })
        // The clear corner and the frame around it show the fill.
        #expect(out[4 + 2] == [255, 255, 255, 255])
        #expect(out[0] == [255, 255, 255, 255])
        #expect(out[8 + 3] == [255, 255, 255, 255])
    }

    @Test func aWindowAsLargeAsTheFrameFillsIt() {
        let image = capture(width: 2, height: 2, window)
        let result = StudioComposite.centred(image, in: PixelSize(width: 2, height: 2), space: displayP3, over: nil)!
        #expect(pixels(result) == window)
    }

    @Test func aWindowLargerThanTheFrameGivesNoPicture() {
        let image = capture(width: 3, height: 2, Array(repeating: [1, 1, 1, 255], count: 6))
        #expect(StudioComposite.centred(image, in: PixelSize(width: 2, height: 2), space: displayP3, over: nil) == nil)
        #expect(StudioComposite.centred(image, in: PixelSize(width: 3, height: 1), space: displayP3, over: nil) == nil)
        #expect(StudioComposite.centred(image, in: PixelSize(width: 3, height: 2), space: displayP3, over: nil) != nil)
    }

    @Test func aCheckerboardWindowIsCopiedWithoutInterpolation() {
        let width = 63
        let height = 41
        let board = (0..<(width * height)).map { index -> [UInt8] in
            (index % width + index / width) % 2 == 0 ? [0, 0, 0, 255] : [255, 255, 255, 255]
        }
        let image = capture(width: width, height: height, board)
        let frame = PixelSize(width: 100, height: 60)
        let result = StudioComposite.centred(
            image, in: frame, space: displayP3, over: .gradient(StudioBackground.gradients[0].gradient))!
        let out = pixels(result)
        // Origin (18, 9).
        for y in 0..<height {
            for x in 0..<width {
                #expect(out[(y + 9) * frame.width + x + 18] == board[y * width + x])
            }
        }
    }

    @Test func cuttingToTheVisibleBoundsThenCentringLandsTheWindowInTheMiddle() {
        // A 2 × 1 window somewhere in a 10 × 8 capture, as ScreenCaptureKit may place it.
        let captured = capture(
            width: 10, height: 8, [Pixel(x: 6, y: 5): [1, 2, 3, 255], Pixel(x: 7, y: 5): [4, 5, 6, 255]])
        let bounds = OneWindowPicture.visibleBounds(of: captured)!
        let cut = captured.cropping(to: CGRect(x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height))!
        let result = StudioComposite.centred(cut, in: PixelSize(width: 6, height: 3), space: displayP3, over: nil)!
        let out = pixels(result)
        // Origin (2, 1).
        #expect(out[6 + 2] == [1, 2, 3, 255])
        #expect(out[6 + 3] == [4, 5, 6, 255])
        #expect(out.enumerated().filter { $0.element[3] != 0 }.map(\.offset) == [8, 9])
    }
}
