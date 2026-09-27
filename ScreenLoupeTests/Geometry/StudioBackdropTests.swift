import CoreGraphics
import Testing

/// A Retina primary display, a non-Retina one left of it and lower, and a Retina one above it.
private let primary = DisplayInfo(id: 1, globalFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2)
private let left = DisplayInfo(id: 2, globalFrame: CGRect(x: -1920, y: -300, width: 1920, height: 1080), scale: 1)
private let above = DisplayInfo(id: 3, globalFrame: CGRect(x: 0, y: 900, width: 3008, height: 1692), scale: 2)
private let converter = DisplayCoordinateConverter(layout: DisplayLayout(displays: [primary, left, above])!)

private let white = StudioBackground.color(.white)

private func placement(
    _ frame: CGRect, background: StudioBackground = white, visible: Bool = true,
    converter: DisplayCoordinateConverter? = converter
) -> StudioBackdrop.Placement? {
    StudioBackdrop.placement(
        studioVisible: visible, background: background, frame: GlobalRect(rect: frame), converter: converter)
}

struct StudioBackdropTests {
    // MARK: Whether it shows

    @Test func theScreenAsBackgroundHasNoBackdrop() {
        #expect(placement(CGRect(x: 100, y: 100, width: 400, height: 300), background: .screen) == nil)
    }

    @Test func aHiddenStudioHasNoBackdrop() {
        #expect(placement(CGRect(x: 100, y: 100, width: 400, height: 300), visible: false) == nil)
    }

    @Test func everyOtherBackgroundHasOne() {
        let backgrounds: [StudioBackground] = [
            .color(.black), .gradient(StudioBackground.gradients[0].gradient),
            .image(BackgroundImage(fileName: "a.png", name: "a.png")),
        ]
        for background in backgrounds {
            let shown = placement(CGRect(x: 100, y: 100, width: 400, height: 300), background: background)
            #expect(shown?.background == background)
            #expect(shown?.display == primary)
        }
    }

    @Test func aFrameOnNoDisplayHasNoBackdrop() {
        #expect(placement(CGRect(x: 5000, y: 5000, width: 400, height: 300)) == nil)
        #expect(placement(CGRect(x: 100, y: 100, width: 400, height: 300), converter: nil) == nil)
    }

    // MARK: Which display

    @Test func itCoversTheWholeDisplayTheFrameIsOn() {
        let shown = placement(CGRect(x: 100, y: 100, width: 400, height: 300))
        #expect(shown?.display.globalFrame == primary.globalFrame)
    }

    @Test func aDisplayLeftOfAndBelowThePrimaryWithNegativeCoordinates() {
        let shown = placement(CGRect(x: -1500, y: -200, width: 600, height: 400))
        #expect(shown?.display == left)
        #expect(shown?.pixelSize == PixelSize(width: 1920, height: 1080))
    }

    @Test func aDisplayAboveThePrimary() {
        let shown = placement(CGRect(x: 200, y: 1200, width: 600, height: 400))
        #expect(shown?.display == above)
        #expect(shown?.pixelSize == PixelSize(width: 6016, height: 3384))
    }

    @Test func aFrameStraddlingTwoDisplaysGoesToTheOneWithTheLargerShare() {
        // 300 pt on the primary, 100 pt on the display to the left.
        #expect(placement(CGRect(x: -100, y: 100, width: 400, height: 300))?.display == primary)
        // 100 pt on the primary, 300 pt on the left.
        #expect(placement(CGRect(x: -300, y: 100, width: 400, height: 300))?.display == left)
    }

    @Test func itFollowsTheFrameToAnotherDisplay() {
        let before = placement(CGRect(x: 100, y: 100, width: 400, height: 300))
        let after = placement(CGRect(x: -1000, y: 100, width: 400, height: 300))
        #expect(before?.display == primary)
        #expect(after?.display == left)
        #expect(before != after)
    }

    @Test func theSameDisplayAndBackgroundIsTheSamePlacement() {
        // Moving the frame within its display draws nothing anew.
        #expect(
            placement(CGRect(x: 100, y: 100, width: 400, height: 300))
                == placement(CGRect(x: 900, y: 500, width: 200, height: 100)))
        // Another background does.
        #expect(
            placement(CGRect(x: 100, y: 100, width: 400, height: 300))
                != placement(CGRect(x: 100, y: 100, width: 400, height: 300), background: .color(.black)))
    }

    // MARK: Its pixels

    @Test func thePixelSizeIsTheWholeDisplayInItsBackingPixels() {
        #expect(StudioBackdrop.pixelSize(of: primary) == PixelSize(width: 2880, height: 1800))
        #expect(StudioBackdrop.pixelSize(of: left) == PixelSize(width: 1920, height: 1080))
        #expect(StudioBackdrop.pixelSize(of: above) == PixelSize(width: 6016, height: 3384))
    }

    @Test func aScaleChangeChangesThePixelSize() {
        // The same display in a scaled mode: the same points, more pixels.
        var scaled = primary
        scaled.scale = 3
        #expect(StudioBackdrop.pixelSize(of: scaled) == PixelSize(width: 4320, height: 2700))
        let layout = DisplayLayout(displays: [scaled])!
        let shown = placement(
            CGRect(x: 100, y: 100, width: 400, height: 300), converter: DisplayCoordinateConverter(layout: layout))
        #expect(shown?.pixelSize == PixelSize(width: 4320, height: 2700))
        #expect(shown != placement(CGRect(x: 100, y: 100, width: 400, height: 300)))
    }

    // MARK: The background over a whole display

    @Test func aWiderImageIsCutAtTheDisplaysSides() {
        // 6000 × 2000 over 2880 × 1800: scaled by 0.9 to 5400 × 1800, 1260 cut on each side.
        let rect = StudioBackground.imageRect(
            CGSize(width: 6000, height: 2000), filling: CGSize(width: 2880, height: 1800))
        #expect(abs(rect.minX - -1260) < 1e-9 && rect.minY == 0)
        #expect(abs(rect.width - 5400) < 1e-9 && abs(rect.height - 1800) < 1e-9)
    }

    @Test func aTallerImageIsCutAtTheDisplaysTopAndBottom() {
        // 1080 × 1920 over 6016 × 3384: scaled by 6016 / 1080, centred vertically.
        let rect = StudioBackground.imageRect(
            CGSize(width: 1080, height: 1920), filling: CGSize(width: 6016, height: 3384))
        #expect(abs(rect.width - 6016) < 1e-9 && abs(rect.minX) < 1e-9)
        #expect(abs(rect.midY - 1692) < 1e-6)
        #expect(rect.minY < 0 && rect.maxY > 3384)
    }

    @Test func anImageOfTheDisplaysProportionsFitsItExactly() {
        let rect = StudioBackground.imageRect(
            CGSize(width: 2880, height: 1800), filling: CGSize(width: 2880, height: 1800))
        #expect(rect == CGRect(x: 0, y: 0, width: 2880, height: 1800))
    }

    @Test func aTinyImageIsScaledUpToCoverTheDisplay() {
        let rect = StudioBackground.imageRect(CGSize(width: 2, height: 1), filling: CGSize(width: 1920, height: 1080))
        #expect(rect.minX <= 0 && rect.minY <= 0 && rect.maxX >= 1920 && rect.maxY >= 1080)
        #expect(abs(rect.height - 1080) < 1e-9 && abs(rect.width - 2160) < 1e-9)
    }

    @Test func theGradientSpansTheWholeDisplay() {
        let line = StudioBackground.gradientLine(in: CGSize(width: 6016, height: 3384))
        #expect(line.start == CGPoint(x: 3008, y: 3384))
        #expect(line.end == CGPoint(x: 3008, y: 0))
    }

    @Test func anImageIsDecodedLargeEnoughForTheLargestDisplaysBackdrop() {
        // The backdrop of the 6016 × 3384 display takes the largest picture there is.
        let largest = StudioComposite.largestPicture(on: [primary, left, above])
        #expect(largest == PixelSize(width: 6016, height: 3384))
        // A 12000 × 8000 photo: covering 6016 × 3384 takes 6016 / 12000, so 6016 on its long side.
        #expect(
            StudioComposite.backgroundMaxPixelSize(image: PixelSize(width: 12000, height: 8000), display: largest)
                == 6016)
    }
}
