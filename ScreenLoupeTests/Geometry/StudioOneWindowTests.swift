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
        #expect(OneWindowMode.picking.after(.unavailable(.notListed)) == .picking)
    }

    @Test func toggleTurnsAChosenWindowOff() {
        #expect(OneWindowMode.on(safari).after(.toggle(studioVisible: true)) == .off)
        #expect(OneWindowMode.on(safari).after(.toggle(studioVisible: false)) == .off)
    }

    @Test func hidingKeepsTheChosenWindow() {
        #expect(OneWindowMode.on(safari).after(.hidden) == .on(safari))
    }

    @Test func theChosenWindowBecomingUnavailableTurnsItOff() {
        #expect(OneWindowMode.on(safari).after(.unavailable(.notListed)) == .off)
        #expect(OneWindowMode.on(notes).after(.unavailable(.notListed)) == .off)
    }

    @Test func eventsThatDontApplyLeaveTheModeAsItIs() {
        #expect(OneWindowMode.on(safari).after(.picked(notes)) == .on(safari))
        #expect(OneWindowMode.on(safari).after(.cancelled) == .on(safari))
        #expect(OneWindowMode.off.after(.picked(safari)) == .off)
        #expect(OneWindowMode.off.after(.cancelled) == .off)
        #expect(OneWindowMode.off.after(.hidden) == .off)
        #expect(OneWindowMode.off.after(.unavailable(.notListed)) == .off)
    }

    @Test func aSessionChooseHideShowAndGone() {
        var mode = OneWindowMode.off
        for (event, expected) in [
            (OneWindowMode.Event.toggle(studioVisible: true), OneWindowMode.picking),
            (.picked(safari), .on(safari)),
            (.hidden, .on(safari)),
            // Shown again, then the window is minimised.
            (.unavailable(.notListed), .off),
            (.unavailable(.notListed), .off),
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

    @Test func pickAnotherWindowPicksAgainFromAChosenWindowOnly() {
        #expect(OneWindowMode.on(safari).after(.pickAnother) == .repicking(safari))
        #expect(OneWindowMode.picking.after(.pickAnother) == .picking)
        #expect(OneWindowMode.repicking(safari).after(.pickAnother) == .repicking(safari))
        #expect(OneWindowMode.off.after(.pickAnother) == .off)
    }

    @Test func aRePickKeepsTheChosenWindow() {
        let mode = OneWindowMode.repicking(safari)
        #expect(mode.chosen == safari)
        #expect(mode.isPicking)
        #expect(!mode.usesFrame)
    }

    @Test func aPickInARePickReplacesTheChosenWindow() {
        #expect(OneWindowMode.repicking(safari).after(.picked(notes)) == .on(notes))
        // The same window picked again.
        #expect(OneWindowMode.repicking(safari).after(.picked(safari)) == .on(safari))
    }

    @Test func escapeInARePickGoesBackToTheChosenWindow() {
        #expect(OneWindowMode.on(safari).after(.pickAnother).after(.cancelled) == .on(safari))
        // Hiding the studio during a re-pick keeps it too.
        #expect(OneWindowMode.repicking(safari).after(.hidden) == .on(safari))
    }

    @Test func theToggleAndEndStopARePickAndOneWindow() {
        #expect(OneWindowMode.repicking(safari).after(.toggle(studioVisible: true)) == .off)
        #expect(OneWindowMode.repicking(safari).after(.end) == .off)
    }

    @Test func theChosenWindowLostDuringARePickEndsOneWindow() {
        #expect(OneWindowMode.repicking(safari).after(.unavailable(.notListed)) == .off)
        #expect(OneWindowMode.repicking(safari).after(.unavailable(.otherScale)) == .off)
    }

    // MARK: A press

    @Test func aPressTakesTheFrameWhileOff() {
        #expect(OneWindowMode.off.press == .frame)
        #expect(OneWindowMode.off.after(.pressed) == .off)
    }

    @Test func aPressDuringTheFirstPickIsRefusedAndThePickingGoesOn() {
        #expect(OneWindowMode.picking.press == .pickFirst)
        #expect(OneWindowMode.picking.after(.pressed) == .picking)
        #expect(OneWindowPress.pickFirstNotice == "Pick a window first")
    }

    @Test func aPressDuringARePickEndsItAndTakesTheChosenWindow() {
        #expect(OneWindowMode.repicking(safari).press == .window(safari))
        #expect(OneWindowMode.repicking(safari).after(.pressed) == .on(safari))
    }

    @Test func aPressWithAWindowChosenTakesIt() {
        #expect(OneWindowMode.on(notes).press == .window(notes))
        #expect(OneWindowMode.on(notes).after(.pressed) == .on(notes))
    }

    // MARK: The window lost

    @Test func anUnavailableWindowTurnsOneWindowOff() {
        for problem in [OneWindowProblem.notListed, .otherScale] {
            #expect(OneWindowMode.on(safari).after(.unavailable(problem)) == .off)
        }
    }

    @Test func losingTheWindowWhileNothingWaitsSaysNothing() {
        // Closed or hidden while idle: off quietly.
        for problem in [OneWindowProblem.notListed, .otherScale] {
            #expect(problem.notice(cancels: false, studioVisible: true) == nil)
        }
    }

    @Test func losingTheWindowDuringACountdownOrAPressSaysWhyNothingWasCaptured() {
        #expect(
            OneWindowProblem.notListed.notice(cancels: true, studioVisible: true) == "Window gone · nothing captured")
        #expect(
            OneWindowProblem.otherScale.notice(cancels: true, studioVisible: true)
                == "Window can't be captured · nothing captured")
    }

    @Test func aCaptureCancelledByHidingTheStudioSaysNothing() {
        for problem in [OneWindowProblem.notListed, .otherScale] {
            for cancels in [false, true] {
                #expect(problem.notice(cancels: cancels, studioVisible: false) == nil)
            }
        }
        // Hiding keeps the chosen window; a later loss while hidden turns it off quietly.
        #expect(OneWindowMode.on(safari).after(.hidden).after(.unavailable(.notListed)) == .off)
    }

    @Test func endTurnsOneWindowOffFromEveryMode() {
        #expect(OneWindowMode.on(safari).after(.end) == .off)
        #expect(OneWindowMode.picking.after(.end) == .off)
        #expect(OneWindowMode.off.after(.end) == .off)
    }

    @Test func theListsRowsFollowTheMode() {
        // Pick Another Window: a window chosen. End One Window: picking or chosen.
        #expect(!OneWindowMode.off.canPickAnother)
        #expect(!OneWindowMode.picking.canPickAnother)
        #expect(!OneWindowMode.repicking(safari).canPickAnother)
        #expect(OneWindowMode.on(safari).canPickAnother)
        #expect(!OneWindowMode.off.canEnd)
        #expect(OneWindowMode.picking.canEnd)
        #expect(OneWindowMode.repicking(safari).canEnd)
        #expect(OneWindowMode.on(safari).canEnd)
    }

    @Test func theFrameIsInUseOnlyWhileOneWindowIsOff() {
        #expect(OneWindowMode.off.usesFrame)
        #expect(!OneWindowMode.picking.usesFrame)
        #expect(!OneWindowMode.on(safari).usesFrame)
    }

    @Test func theFrameComesBackWithEveryWayOneWindowEnds() {
        let ends: [(OneWindowMode, OneWindowMode.Event)] = [
            (.on(safari), .toggle(studioVisible: true)), (.on(safari), .toggle(studioVisible: false)),
            (.on(notes), .unavailable(.otherScale)), (.on(safari), .end), (.picking, .end), (.picking, .cancelled),
            (.picking, .hidden), (.picking, .toggle(studioVisible: false)),
        ]
        for (mode, event) in ends {
            #expect(mode.after(event).usesFrame, "\(mode) \(event)")
        }
        // Hiding the studio keeps a chosen window, and the frame stays out of use.
        #expect(!OneWindowMode.on(safari).after(.hidden).usesFrame)
        // Picking another window, and cancelling it, keep the frame out of use.
        #expect(!OneWindowMode.repicking(safari).after(.cancelled).usesFrame)
        #expect(!OneWindowMode.on(safari).after(.pickAnother).usesFrame)
        // Turning on with the studio hidden doesn't start.
        #expect(OneWindowMode.off.after(.toggle(studioVisible: false)).usesFrame)
    }

    @Test func theMenusNoteSaysWhy() {
        #expect(
            OneWindowMode.frameControlsNote
                == "Not used in One Window: the picture is the window alone, on transparency.")
    }
}

struct OneWindowPictureTests {
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

    // MARK: The picture

    /// A 2 × 2 window: two opaque pixels, a half-transparent shadow pixel and a clear corner.
    private let window: [[UInt8]] = [
        [10, 20, 30, 255], [0, 0, 0, 128],
        [7, 200, 99, 255], [0, 0, 0, 0],
    ]

    /// The capture cut to its visible bounds and put into `space` with its alpha, as One Window's
    /// picture is made.
    private func picture(of captured: CGImage, in space: CGColorSpace) -> CGImage? {
        guard let bounds = OneWindowPicture.visibleBounds(of: captured),
            let cut = captured.cropping(
                to: CGRect(x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height))
        else { return nil }
        return StudioComposite.converted(cut, to: space, keepingAlpha: true)
    }

    @Test func thePictureIsExactlyTheVisiblePixelsOnTransparency() {
        // The window somewhere in a 9 × 7 capture, as ScreenCaptureKit may place it.
        var set: [Pixel: [UInt8]] = [:]
        for (index, value) in window.enumerated() { set[Pixel(x: 4 + index % 2, y: 2 + index / 2)] = value }
        let result = picture(of: capture(width: 9, height: 7, set), in: displayP3)!
        // The clear corner is inside the bounds the other three pixels span.
        #expect(result.width == 2 && result.height == 2)
        #expect(StudioComposite.hasAlpha(result))
        #expect(result.colorSpace == displayP3)
        #expect(pixels(result) == window)
    }

    @Test func aShadowWiderBelowGivesThePictureItsWholeShadow() {
        // A 2 × 2 window with a shadow one pixel at the sides, none above, two below, in a 10 × 10
        // capture: the picture is 4 × 4, the window at its top middle, every shadow pixel kept.
        var set: [Pixel: [UInt8]] = [:]
        for y in 3...6 {
            for x in 3...6 { set[Pixel(x: x, y: y)] = [0, 0, 0, 64] }
        }
        for y in 3...4 {
            for x in 4...5 { set[Pixel(x: x, y: y)] = [9, 9, 9, 255] }
        }
        let result = picture(of: capture(width: 10, height: 10, set), in: displayP3)!
        #expect(result.width == 4 && result.height == 4)
        let out = pixels(result)
        #expect(out[1] == [9, 9, 9, 255] && out[2] == [9, 9, 9, 255])
        #expect(out[4 + 1] == [9, 9, 9, 255] && out[4 + 2] == [9, 9, 9, 255])
        for index in [0, 3, 4, 7, 8, 11, 12, 13, 14, 15] {
            #expect(out[index] == [0, 0, 0, 64], "pixel \(index)")
        }
    }

    @Test func aPictureConvertedIntoTheDisplaysSpaceKeepsItsTransparency() {
        // Captured in sRGB, the display in Display P3: converted, alpha unchanged.
        let result = picture(of: capture(width: 2, height: 2, space: sRGB, window), in: displayP3)!
        #expect(result.colorSpace == displayP3)
        #expect(StudioComposite.hasAlpha(result))
        let out = pixels(result)
        #expect(out.map { $0[3] } == [255, 128, 255, 0])
        // Black stays black, half covered.
        #expect(out[1] == [0, 0, 0, 128])
    }

    @Test func aCheckerboardWindowIsCopiedWithoutInterpolation() {
        let width = 63
        let height = 41
        let board = (0..<(width * height)).map { index -> [UInt8] in
            (index % width + index / width) % 2 == 0 ? [0, 0, 0, 255] : [255, 255, 255, 255]
        }
        let result = picture(of: capture(width: width, height: height, board), in: displayP3)!
        #expect(result.width == width && result.height == height)
        #expect(pixels(result) == board)
    }

    @Test func aPictureAtTwoXIsTwiceAsLargeInPixelsAsAtOneX() {
        // The same 3 × 2 pt window, opaque, captured at 1× and at 2×: the picture is its pixels.
        for scale in [1, 2] {
            let width = 3 * scale
            let height = 2 * scale
            var set: [Pixel: [UInt8]] = [:]
            for y in 0..<height {
                for x in 0..<width { set[Pixel(x: x + 5, y: y + 5)] = [1, 2, 3, 255] }
            }
            let result = picture(of: capture(width: width + 10, height: height + 10, set), in: displayP3)!
            #expect(result.width == width && result.height == height)
        }
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
    @Test func aWindowListedAtItsDisplaysScaleIsTaken() {
        #expect(OneWindowPicture.shot(windowScale: 2, displayScale: 2) == .window)
        #expect(OneWindowPicture.shot(windowScale: 1, displayScale: 1) == .window)
    }

    @Test func aWindowNotListedIsUnavailable() {
        #expect(OneWindowPicture.shot(windowScale: nil, displayScale: 2) == .unavailable(.notListed))
        #expect(OneWindowPicture.shot(windowScale: nil, displayScale: 1) == .unavailable(.notListed))
    }

    @Test func aWindowOnADisplayOfAnotherScaleIsUnavailable() {
        #expect(OneWindowPicture.shot(windowScale: 1, displayScale: 2) == .unavailable(.otherScale))
        #expect(OneWindowPicture.shot(windowScale: 2, displayScale: 1) == .unavailable(.otherScale))
        #expect(OneWindowPicture.shot(windowScale: 1.5, displayScale: 2) == .unavailable(.otherScale))
    }

    @Test func anUnavailableWindowReleasesItAndBringsTheFrameBack() {
        for problem in [OneWindowProblem.notListed, .otherScale] {
            #expect(OneWindowMode.on(safari).after(.unavailable(problem)) == .off)
            #expect(OneWindowMode.on(safari).after(.unavailable(problem)).usesFrame)
        }
    }
}
