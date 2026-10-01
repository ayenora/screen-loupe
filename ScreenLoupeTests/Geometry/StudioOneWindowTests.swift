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

    @Test func anUnavailableWindowWhilePickingChangesNothing() {
        #expect(OneWindowMode.picking.after(.unavailable) == .picking)
    }

    @Test func toggleTurnsAChosenWindowOff() {
        #expect(OneWindowMode.on(safari).after(.toggle(studioVisible: true)) == .off)
        #expect(OneWindowMode.on(safari).after(.toggle(studioVisible: false)) == .off)
    }

    @Test func hidingKeepsTheChosenWindow() {
        #expect(OneWindowMode.on(safari).after(.hidden) == .on(safari))
    }

    @Test func theChosenWindowBecomingUnavailableTurnsItOff() {
        #expect(OneWindowMode.on(safari).after(.unavailable) == .off)
        #expect(OneWindowMode.on(notes).after(.unavailable) == .off)
    }

    @Test func eventsThatDontApplyLeaveTheModeAsItIs() {
        #expect(OneWindowMode.on(safari).after(.picked(notes)) == .on(safari))
        #expect(OneWindowMode.on(safari).after(.cancelled) == .on(safari))
        #expect(OneWindowMode.off.after(.picked(safari)) == .off)
        #expect(OneWindowMode.off.after(.cancelled) == .off)
        #expect(OneWindowMode.off.after(.hidden) == .off)
        #expect(OneWindowMode.off.after(.unavailable) == .off)
    }

    @Test func aSessionChooseHideShowAndGone() {
        var mode = OneWindowMode.off
        for (event, expected) in [
            (OneWindowMode.Event.toggle(studioVisible: true), OneWindowMode.picking),
            (.picked(safari), .on(safari)),
            (.hidden, .on(safari)),
            // Shown again, then the window is minimised.
            (.unavailable, .off),
            (.unavailable, .off),
            (.toggle(studioVisible: true), .picking),
            (.picked(notes), .on(notes)),
        ] {
            mode = mode.after(event)
            #expect(mode == expected)
        }
    }

    @Test func theChosenWindowAndPicking() {
        #expect(OneWindowMode.on(safari).chosen == safari)
        #expect(OneWindowMode.off.chosen == nil)
        #expect(OneWindowMode.picking.chosen == nil)
        #expect(OneWindowMode.picking.isPicking)
        #expect(!OneWindowMode.on(safari).isPicking)
    }

    @Test func theShadowChoiceIsOpenOnlyWhileOneWindowIsOn() {
        #expect(!OneWindowMode.off.allowsShadowChoice)
        #expect(OneWindowMode.picking.allowsShadowChoice)
        #expect(OneWindowMode.on(safari).allowsShadowChoice)
    }

    @Test func theShadowChoiceFollowsEveryWayOneWindowEnds() {
        // Let go, the window gone, the picker cancelled or hidden: greyed out again.
        let ends: [(OneWindowMode, OneWindowMode.Event)] = [
            (.on(safari), .toggle(studioVisible: true)), (.on(notes), .unavailable),
            (.picking, .cancelled), (.picking, .hidden), (.picking, .toggle(studioVisible: false)),
        ]
        for (mode, event) in ends {
            #expect(!mode.after(event).allowsShadowChoice, "\(mode) \(event)")
        }
        // Hiding the studio keeps a chosen window, and its shadow choice with it.
        #expect(OneWindowMode.on(safari).after(.hidden).allowsShadowChoice)
        // Turning on with the studio hidden doesn't open it.
        #expect(!OneWindowMode.off.after(.toggle(studioVisible: false)).allowsShadowChoice)
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

    // MARK: Capture room

    @Test func theCaptureHasRoomAroundTheWindowOnEverySide() {
        // 128 pt of room: 256 px at 2×, 128 px at 1×.
        #expect(
            OneWindowPicture.captureSize(window: PixelSize(width: 800, height: 1200), scale: 2)
                == PixelSize(width: 800 + 512, height: 1200 + 512))
        #expect(
            OneWindowPicture.captureSize(window: PixelSize(width: 400, height: 600), scale: 1)
                == PixelSize(width: 400 + 256, height: 600 + 256))
        // A fractional scale rounds the room up: 128 × 1.5 = 192.
        #expect(
            OneWindowPicture.captureSize(window: PixelSize(width: 3, height: 5), scale: 1.5)
                == PixelSize(width: 3 + 384, height: 5 + 384))
        #expect(
            OneWindowPicture.captureSize(window: PixelSize(width: 0, height: 0), scale: 2)
                == PixelSize(width: 512, height: 512))
    }

    @Test func theRoomHoldsTheLargestShadowWithTheToleranceToSpare() {
        // The window with a shadow of `room − fillTolerance` points on every side, at its own size,
        // doesn't count as scaled down; one pixel more does.
        for scale: CGFloat in [1, 2, 3] {
            let window = PixelSize(width: 1000, height: 700)
            let capture = OneWindowPicture.captureSize(window: window, scale: scale)
            let shadow = Int((OneWindowPicture.room - OneWindowPicture.fillTolerance) * scale)
            let visible = PixelSize(width: window.width + 2 * shadow, height: window.height + 2 * shadow)
            #expect(!OneWindowPicture.isScaledDown(visible: visible, capture: capture, scale: scale))
            #expect(
                OneWindowPicture.isScaledDown(
                    visible: PixelSize(width: visible.width + 1, height: visible.height), capture: capture, scale: scale
                ))
            #expect(
                OneWindowPicture.isScaledDown(
                    visible: PixelSize(width: visible.width, height: visible.height + 1), capture: capture, scale: scale
                ))
        }
    }

    @Test func aCaptureFillingAnAxisIsScaledDown() {
        let capture = PixelSize(width: 1312, height: 1712)
        // Filling the width exactly, the height with room left: a wide window scaled to fit.
        #expect(OneWindowPicture.isScaledDown(visible: PixelSize(width: 1312, height: 900), capture: capture, scale: 2))
        // The faintest shadow pixels rounded away: a few pixels short still counts.
        #expect(OneWindowPicture.isScaledDown(visible: PixelSize(width: 800, height: 1708), capture: capture, scale: 2))
        // A window without a shadow, however it sits in the output, doesn't.
        #expect(
            !OneWindowPicture.isScaledDown(visible: PixelSize(width: 800, height: 1200), capture: capture, scale: 2))
        #expect(!OneWindowPicture.isScaledDown(visible: PixelSize(width: 1, height: 1), capture: capture, scale: 2))
    }

    // MARK: Picture size

    @Test func aWindowWithItsShadowInsideTheFrameKeepsTheFramesSize() {
        // A 1920 × 1080 preset with a background: the picture is exactly the preset.
        let frame = PixelSize(width: 1920, height: 1080)
        #expect(OneWindowPicture.pictureSize(frame: frame, visible: PixelSize(width: 1200, height: 800)) == frame)
        #expect(OneWindowPicture.pictureSize(frame: frame, visible: PixelSize(width: 1, height: 1)) == frame)
    }

    @Test func aWindowWithItsShadowAsLargeAsTheFrameKeepsTheFramesSize() {
        let frame = PixelSize(width: 1920, height: 1080)
        #expect(OneWindowPicture.pictureSize(frame: frame, visible: frame) == frame)
    }

    @Test func theShadowGrowsOnlyTheAxisItOverflows() {
        let frame = PixelSize(width: 800, height: 1200)
        #expect(
            OneWindowPicture.pictureSize(frame: frame, visible: PixelSize(width: 1000, height: 1100))
                == PixelSize(width: 1000, height: 1200))
        #expect(
            OneWindowPicture.pictureSize(frame: frame, visible: PixelSize(width: 700, height: 1500))
                == PixelSize(width: 800, height: 1500))
    }

    @Test func theShadowGrowsBothAxes() {
        // Fit to Window on a 400 × 600 pt window at 2×, then One Window with its shadow.
        let frame = PixelSize(width: 800, height: 1200)
        #expect(
            OneWindowPicture.pictureSize(frame: frame, visible: PixelSize(width: 1025, height: 1463))
                == PixelSize(width: 1025, height: 1463))
    }

    @Test func pictureSizesAgreeAt1xAnd2x() {
        // A 400 × 300 pt frame holding the window exactly, its shadow 56 pt at the sides, 36 above,
        // 76 below.
        for scale in [1, 2] {
            let frame = PixelSize(width: 400 * scale, height: 300 * scale)
            let visible = PixelSize(width: (400 + 112) * scale, height: (300 + 112) * scale)
            #expect(OneWindowPicture.pictureSize(frame: frame, visible: visible) == visible)
        }
    }

    @Test func aWindowLargerThanTheFrameComesAtItsOwnSize() {
        // A 400 × 300 pt frame at 2×, a 1200 × 800 pt window without its shadow: the window's size.
        let frame = PixelSize(width: 800, height: 600)
        let window = PixelSize(width: 2400, height: 1600)
        #expect(OneWindowPicture.pictureSize(frame: frame, visible: window) == window)
        #expect(OneWindowPicture.centredOrigin(of: window, in: window) == (0, 0))
        // One pixel over on each axis.
        #expect(
            OneWindowPicture.pictureSize(frame: frame, visible: PixelSize(width: 801, height: 601))
                == PixelSize(width: 801, height: 601))
    }

    @Test func aWindowLargerOnOneAxisTakesThatAxisAndCentresOnTheOther() {
        // Wider than the frame, shorter: as wide as the window, as tall as the frame, centred in it.
        let frame = PixelSize(width: 1000, height: 1000)
        let wide = PixelSize(width: 1500, height: 401)
        let picture = OneWindowPicture.pictureSize(frame: frame, visible: wide)
        #expect(picture == PixelSize(width: 1500, height: 1000))
        // 1000 − 401 = 599: 299 above, 300 below.
        #expect(OneWindowPicture.centredOrigin(of: wide, in: picture) == (0, 299))
        // Taller, narrower.
        let tall = PixelSize(width: 333, height: 1201)
        let tallPicture = OneWindowPicture.pictureSize(frame: frame, visible: tall)
        #expect(tallPicture == PixelSize(width: 1000, height: 1201))
        #expect(OneWindowPicture.centredOrigin(of: tall, in: tallPicture) == (333, 0))
    }

    @Test func aWindowWithItsShadowLargerThanTheFrameTakesTheShadowToo() {
        // A 600 × 400 pt window at 2× with an asymmetric shadow — 56 pt at the sides, 36 above,
        // 76 below — on a 300 × 200 pt frame: the picture is the window with its whole shadow.
        let frame = PixelSize(width: 600, height: 400)
        let visible = PixelSize(width: (600 + 112) * 2, height: (400 + 36 + 76) * 2)
        #expect(OneWindowPicture.pictureSize(frame: frame, visible: visible) == visible)
        // The same at 1×.
        let visible1x = PixelSize(width: 600 + 112, height: 400 + 36 + 76)
        #expect(
            OneWindowPicture.pictureSize(frame: PixelSize(width: 300, height: 200), visible: visible1x) == visible1x)
    }

    @Test func aWindowAsLargeAsTheFrameIsTheFrame() {
        let frame = PixelSize(width: 1441, height: 901)
        #expect(OneWindowPicture.pictureSize(frame: frame, visible: frame) == frame)
        #expect(OneWindowPicture.centredOrigin(of: frame, in: frame) == (0, 0))
    }

    @Test func aDegenerateFrameTakesTheVisibleSize() {
        #expect(
            OneWindowPicture.pictureSize(frame: PixelSize(width: 0, height: 0), visible: PixelSize(width: 3, height: 2))
                == PixelSize(width: 3, height: 2))
        #expect(
            OneWindowPicture.pictureSize(frame: PixelSize(width: 5, height: 0), visible: PixelSize(width: 3, height: 2))
                == PixelSize(width: 5, height: 2))
        #expect(
            OneWindowPicture.pictureSize(frame: PixelSize(width: 0, height: 0), visible: PixelSize(width: 0, height: 0))
                == PixelSize(width: 0, height: 0))
    }

    @Test func aGrownAxisIsFilledAndTheOtherStillCentresWithTheOddPixelRightAndBelow() {
        // Grown in width: the cut fills it. The height has 1200 − 1101 = 99 left: 49 above, 50 below.
        let frame = PixelSize(width: 800, height: 1200)
        let visible = PixelSize(width: 1001, height: 1101)
        let picture = OneWindowPicture.pictureSize(frame: frame, visible: visible)
        #expect(OneWindowPicture.centredOrigin(of: visible, in: picture) == (0, 49))
        // Grown in height, an odd width left over: 800 − 701 = 99, 49 left, 50 right.
        let tall = PixelSize(width: 701, height: 1301)
        #expect(
            OneWindowPicture.centredOrigin(of: tall, in: OneWindowPicture.pictureSize(frame: frame, visible: tall))
                == (49, 0))
        // Grown in both: the cut is the picture.
        let large = PixelSize(width: 1001, height: 1301)
        #expect(
            OneWindowPicture.centredOrigin(of: large, in: OneWindowPicture.pictureSize(frame: frame, visible: large))
                == (0, 0))
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

    @Test func aShadowLargerAtTheBottomGrowsThePictureAndTheFillCoversAllOfIt() {
        // Fit to Window: a 2 × 2 frame exactly the window. Captured with a shadow one pixel at the
        // sides, none above, two below, in a 10 × 10 capture: visible 4 × 4.
        var pixelsByPlace: [Pixel: [UInt8]] = [:]
        for y in 3...6 {
            for x in 3...6 { pixelsByPlace[Pixel(x: x, y: y)] = [0, 0, 0, 64] }
        }
        for y in 3...4 {
            for x in 4...5 { pixelsByPlace[Pixel(x: x, y: y)] = [9, 9, 9, 255] }
        }
        let captured = capture(width: 10, height: 10, pixelsByPlace)
        let bounds = OneWindowPicture.visibleBounds(of: captured)!
        #expect(bounds == PixelRect(x: 3, y: 3, width: 4, height: 4))
        let frame = PixelSize(width: 2, height: 2)
        let size = OneWindowPicture.pictureSize(frame: frame, visible: bounds.size)
        #expect(size == PixelSize(width: 4, height: 4))
        let cut = captured.cropping(to: CGRect(x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height))!
        let result = StudioComposite.centred(cut, in: size, space: displayP3, over: .color(.white))!
        #expect(result.width == 4 && result.height == 4)
        let out = pixels(result)
        #expect(out.allSatisfy { $0[3] == 255 })
        // The window's pixels unchanged at the top middle, the shadow over white everywhere else.
        #expect(out[1] == [9, 9, 9, 255] && out[2] == [9, 9, 9, 255])
        #expect(out[4 + 1] == [9, 9, 9, 255] && out[4 + 2] == [9, 9, 9, 255])
        for index in [0, 3, 4, 7, 8, 11, 12, 15] {
            #expect(out[index][0...2].allSatisfy { abs(Int($0) - 191) <= 1 }, "pixel \(index)")
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

private func listed(
    _ frame: CGRect, onScreen: Bool = true, layer: Int = 0, alpha: Double = 1
) -> ScreenWindow {
    ScreenWindow(id: 42, frame: frame, layer: layer, isOnScreen: onScreen, alpha: alpha)
}

struct OneWindowWatchTests {
    private let frame = CGRect(x: 100, y: 200, width: 640, height: 480)

    @Test func aWindowOnScreenShowsWhereItIs() {
        var watch = OneWindowWatch()
        #expect(watch.read(listed(frame)) == .shows(frame))
        // Moved and resized: the next read follows.
        let moved = CGRect(x: 130, y: 180, width: 700, height: 500)
        #expect(watch.read(listed(moved)) == .shows(moved))
    }

    @Test func aWindowOnADisplayWithANegativeOriginShows() {
        var watch = OneWindowWatch()
        let left = CGRect(x: -1800, y: -300, width: 800, height: 600)
        #expect(watch.read(listed(left)) == .shows(left))
    }

    @Test func oneOddReadWaitsTwoInARowRelease() {
        var watch = OneWindowWatch()
        #expect(watch.read(nil) == .unsure)
        #expect(watch.read(nil) == .unavailable)
    }

    @Test func aGoodReadBetweenOddOnesStartsTheCountAgain() {
        var watch = OneWindowWatch()
        #expect(watch.read(nil) == .unsure)
        #expect(watch.read(listed(frame)) == .shows(frame))
        #expect(watch.badReads == 0)
        #expect(watch.read(nil) == .unsure)
        #expect(watch.read(listed(frame)) == .shows(frame))
    }

    @Test func closedMinimisedHiddenOrOnAnotherSpaceReleases() {
        // Closed: not listed. Minimised, hidden with its app, on another Space: off screen, or
        // listed with empty bounds.
        for read in [
            nil, listed(frame, onScreen: false), listed(.zero, onScreen: false), listed(.zero),
            listed(CGRect(x: 100, y: 200, width: 0, height: 480)),
        ] {
            var watch = OneWindowWatch()
            #expect(watch.read(read) == .unsure)
            #expect(watch.read(read) == .unavailable)
        }
    }

    @Test func aWindowFadedOutOrNotOrdinaryReleases() {
        for read in [listed(frame, alpha: 0), listed(frame, layer: 3), listed(frame, layer: -1)] {
            var watch = OneWindowWatch()
            #expect(watch.read(read) == .unsure)
            #expect(watch.read(read) == .unavailable)
        }
    }

    @Test func differentOddReadsInARowRelease() {
        var watch = OneWindowWatch()
        #expect(watch.read(listed(frame, onScreen: false)) == .unsure)
        #expect(watch.read(nil) == .unavailable)
    }

    @Test func aHalfTransparentWindowStillShows() {
        var watch = OneWindowWatch()
        #expect(watch.read(listed(frame, alpha: 0.5)) == .shows(frame))
    }
}

struct OneWindowOutlineTests {
    private let label = CGSize(width: 60, height: 16)
    /// A 1440 × 900 pt display's visible frame under a 25 pt menu bar.
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)

    @Test func theLineIsJustOutsideTheWindow() {
        let window = CGRect(x: 200, y: 100, width: 400, height: 300)
        let outline = OneWindowOutline(window: window, lineWidth: 2, labelSize: label, screen: screen)
        #expect(outline.line == CGRect(x: 198, y: 98, width: 404, height: 304))
        let thin = OneWindowOutline(window: window, lineWidth: 1, labelSize: label, screen: screen)
        #expect(thin.line == CGRect(x: 199, y: 99, width: 402, height: 302))
    }

    @Test func theLabelSitsAboveTheTopLeftCorner() {
        let window = CGRect(x: 200, y: 100, width: 400, height: 300)
        let outline = OneWindowOutline(window: window, lineWidth: 2, labelSize: label, screen: screen)
        #expect(!outline.labelInside)
        // Level with the line's left edge, 6 pt above its top.
        #expect(outline.label == CGRect(x: 198, y: 402 + 6, width: 60, height: 16))
    }

    @Test func thePanelHoldsTheLineItsHaloAndTheLabel() {
        let window = CGRect(x: 200, y: 100, width: 400, height: 300)
        let outline = OneWindowOutline(window: window, lineWidth: 2, labelSize: label, screen: screen)
        #expect(outline.panel == CGRect(x: 197, y: 97, width: 406, height: 424 - 97))
        #expect(outline.panel.contains(outline.label))
        #expect(outline.panel.contains(outline.line))
    }

    @Test func withNoRoomAboveTheLabelGoesInsideTheTopLeftCorner() {
        // A window just under the menu bar: 875 − 6 is the highest a label may reach.
        let window = CGRect(x: 0, y: 75, width: 800, height: 800)
        let outline = OneWindowOutline(window: window, lineWidth: 2, labelSize: label, screen: screen)
        #expect(outline.labelInside)
        #expect(outline.label == CGRect(x: 6, y: 875 - 6 - 16, width: 60, height: 16))
        #expect(outline.panel.contains(outline.label))
    }

    @Test func theLabelGoesInsideExactlyWhenItWouldPassTheMargin() {
        // Top of the line at 875 − 6 − 16 − 6 = 847: the label just fits above.
        let fits = CGRect(x: 300, y: 400, width: 200, height: 445)
        #expect(!OneWindowOutline(window: fits, lineWidth: 2, labelSize: label, screen: screen).labelInside)
        let over = CGRect(x: 300, y: 400, width: 200, height: 446)
        #expect(OneWindowOutline(window: over, lineWidth: 2, labelSize: label, screen: screen).labelInside)
    }

    @Test func aWindowReachingAboveTheScreenKeepsItsLabelOnScreen() {
        // Top off the screen: the label goes inside, below the screen's top.
        let window = CGRect(x: 300, y: 500, width: 400, height: 600)
        let outline = OneWindowOutline(window: window, lineWidth: 1, labelSize: label, screen: screen)
        #expect(outline.labelInside)
        #expect(outline.label.maxY == CGFloat(875 - 6))
    }

    @Test func aWindowPartlyOffTheScreenSidewaysKeepsItsLabelOnScreen() {
        let left = CGRect(x: -300, y: 100, width: 500, height: 300)
        #expect(OneWindowOutline(window: left, lineWidth: 2, labelSize: label, screen: screen).label.minX == 6)
        let right = CGRect(x: 1400, y: 100, width: 500, height: 300)
        #expect(
            OneWindowOutline(window: right, lineWidth: 2, labelSize: label, screen: screen).label.maxX
                == CGFloat(1440 - 6))
    }

    @Test func aDisplayWithNegativeCoordinates() {
        // A display left of and below the primary one.
        let secondary = CGRect(x: -1920, y: -1080, width: 1920, height: 1055)
        let window = CGRect(x: -1500, y: -900, width: 600, height: 400)
        let outline = OneWindowOutline(window: window, lineWidth: 2, labelSize: label, screen: secondary)
        #expect(!outline.labelInside)
        #expect(outline.label == CGRect(x: -1502, y: -498 + 6, width: 60, height: 16))
        // Its top at the display's top: inside.
        let high = CGRect(x: -1900, y: -600, width: 600, height: 575)
        let inside = OneWindowOutline(window: high, lineWidth: 2, labelSize: label, screen: secondary)
        #expect(inside.labelInside)
        #expect(inside.label == CGRect(x: -1894, y: -25 - 6 - 16, width: 60, height: 16))
    }

    @Test func aWindowOnHalfPointsAtTwoXPutsTheLabelOnWholePoints() {
        // A Retina window may sit on half points.
        let window = CGRect(x: 100.5, y: 200.5, width: 300, height: 200)
        let outline = OneWindowOutline(window: window, lineWidth: 1, labelSize: label, screen: screen)
        #expect(outline.line == CGRect(x: 99.5, y: 199.5, width: 302, height: 202))
        #expect(outline.label.minX == outline.label.minX.rounded())
        #expect(outline.label.minY == outline.label.minY.rounded())
    }

    @Test func aLabelWiderThanTheWindowStillStartsAtItsLeft() {
        let window = CGRect(x: 400, y: 100, width: 30, height: 30)
        let wide = CGSize(width: 180, height: 16)
        let outline = OneWindowOutline(window: window, lineWidth: 2, labelSize: wide, screen: screen)
        #expect(outline.label.minX == 398)
        // From the halo's left edge, 1 pt left of the label, to the label's right.
        #expect(outline.panel == CGRect(x: 397, y: 97, width: 181, height: 132 + 6 + 16 - 97))
    }
}

struct OneWindowShotTests {
    @Test func aWindowListedAtTheFramesScaleIsTaken() {
        #expect(OneWindowPicture.shot(windowScale: 2, frameScale: 2) == .window)
        #expect(OneWindowPicture.shot(windowScale: 1, frameScale: 1) == .window)
    }

    @Test func aWindowNotListedFallsBackToTheFrame() {
        #expect(OneWindowPicture.shot(windowScale: nil, frameScale: 2) == .frameInstead(.notListed))
        #expect(OneWindowPicture.shot(windowScale: nil, frameScale: 1) == .frameInstead(.notListed))
    }

    @Test func aWindowOnADisplayOfAnotherScaleFallsBackToTheFrame() {
        #expect(OneWindowPicture.shot(windowScale: 1, frameScale: 2) == .frameInstead(.otherScale))
        #expect(OneWindowPicture.shot(windowScale: 2, frameScale: 1) == .frameInstead(.otherScale))
        #expect(OneWindowPicture.shot(windowScale: 1.5, frameScale: 2) == .frameInstead(.otherScale))
    }

    @Test func fallingBackReleasesTheWindow() {
        // The press's fallback turns One Window off, whatever the problem.
        #expect(OneWindowMode.on(safari).after(.unavailable) == .off)
    }
}
