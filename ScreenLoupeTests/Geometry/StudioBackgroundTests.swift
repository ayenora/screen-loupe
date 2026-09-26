import CoreGraphics
import Foundation
import Testing

/// Decodes `background` as the settings do, through `KeyedDecodingContainer.studioBackground`.
private struct Saved: Decodable {
    let background: StudioBackground

    private enum CodingKeys: String, CodingKey { case background }

    init(from decoder: Decoder) throws {
        background = try decoder.container(keyedBy: CodingKeys.self).studioBackground(.background)
    }
}

private func decoded(_ json: String) throws -> StudioBackground {
    try JSONDecoder().decode(Saved.self, from: Data(json.utf8)).background
}

private func saved(_ background: StudioBackground) throws -> String {
    let data = try JSONEncoder().encode(background)
    return "{\"background\": \(String(decoding: data, as: UTF8.self))}"
}

struct StudioBackgroundTests {
    // MARK: What it leaves out

    @Test func onlyTheScreenKeepsTheWallpaper() {
        #expect(!StudioBackground.screen.leavesOutWallpaper)
        #expect(StudioBackground.color(.white).leavesOutWallpaper)
        #expect(StudioBackground.gradient(StudioBackground.gradients[0].gradient).leavesOutWallpaper)
        #expect(StudioBackground.image(BackgroundImage(fileName: "a.png", name: "a.png")).leavesOutWallpaper)
    }

    @Test func aColourOfTheListIsNotCustom() {
        for entry in StudioBackground.colors {
            #expect(!StudioBackground.color(entry.color).isCustomColor)
        }
        #expect(StudioBackground.color(BackgroundColor(10, 20, 30)).isCustomColor)
        #expect(!StudioBackground.screen.isCustomColor)
        #expect(!StudioBackground.gradient(StudioBackground.gradients[0].gradient).isCustomColor)
    }

    @Test func theListsOfferWhiteLightGrayAndBlackAndDistinctGradients() {
        let colors = StudioBackground.colors.map(\.color)
        #expect(colors.contains(.white) && colors.contains(.lightGray) && colors.contains(.black))
        #expect(Set(colors).count == colors.count)
        let gradients = StudioBackground.gradients.map(\.gradient)
        #expect(gradients.count >= 2)
        #expect(Set(gradients).count == gradients.count)
        #expect(gradients.allSatisfy { $0.top != $0.bottom })
    }

    // MARK: Gradient

    @Test func theGradientRunsFromTheTopEdgeToTheBottomEdge() {
        let line = StudioBackground.gradientLine(in: CGSize(width: 2880, height: 1800))
        // CoreGraphics is y up: the top edge is y = height.
        #expect(line.start == CGPoint(x: 1440, y: 1800))
        #expect(line.end == CGPoint(x: 1440, y: 0))
    }

    @Test func theGradientLineOfAOnePixelPicture() {
        let line = StudioBackground.gradientLine(in: CGSize(width: 1, height: 1))
        #expect(line.start == CGPoint(x: 0.5, y: 1))
        #expect(line.end == CGPoint(x: 0.5, y: 0))
    }

    // MARK: Image

    @Test func aWiderImageCoversThePictureAndIsCutAtTheSides() {
        // 4000 × 1000 into 1000 × 500: scaled by 0.5 to 2000 × 500, 500 cut on each side.
        let rect = StudioBackground.imageRect(
            CGSize(width: 4000, height: 1000), filling: CGSize(width: 1000, height: 500))
        #expect(rect == CGRect(x: -500, y: 0, width: 2000, height: 500))
    }

    @Test func aTallerImageCoversThePictureAndIsCutAtTopAndBottom() {
        // 1000 × 3000 into 2880 × 1800: scaled by 2.88 to 2880 × 8640.
        let rect = StudioBackground.imageRect(
            CGSize(width: 1000, height: 3000), filling: CGSize(width: 2880, height: 1800))
        #expect(rect.width == CGFloat(2880))
        #expect(abs(rect.height - 8640) < 1e-9)
        #expect(rect.minX == 0)
        #expect(abs(rect.midY - 900) < 1e-9)
    }

    @Test func aSmallerImageIsScaledUpToCover() {
        let rect = StudioBackground.imageRect(CGSize(width: 100, height: 50), filling: CGSize(width: 1200, height: 630))
        // The height leads: 630 / 50 = 12.6 against 1200 / 100 = 12.
        #expect(abs(rect.height - 630) < 1e-9)
        #expect(abs(rect.width - 1260) < 1e-9)
        #expect(abs(rect.minX - -30) < 1e-9)
        #expect(rect.minY == 0)
    }

    @Test func anImageOfThePicturesProportionsFillsItExactly() {
        let rect = StudioBackground.imageRect(
            CGSize(width: 1440, height: 900), filling: CGSize(width: 2880, height: 1800))
        #expect(rect == CGRect(x: 0, y: 0, width: 2880, height: 1800))
    }

    @Test func anImageAlwaysCoversTheWholePicture() {
        let picture = CGSize(width: 1280, height: 800)
        for image in [CGSize(width: 1, height: 1000), CGSize(width: 1000, height: 1), CGSize(width: 333, height: 777)] {
            let rect = StudioBackground.imageRect(image, filling: picture)
            #expect(rect.minX <= 1e-9 && rect.minY <= 1e-9)
            #expect(rect.maxX >= picture.width - 1e-9 && rect.maxY >= picture.height - 1e-9)
            // Proportions kept.
            #expect(abs(rect.width / rect.height - image.width / image.height) < 1e-9)
        }
    }

    @Test func anEmptyImageDrawsNothing() {
        let picture = CGSize(width: 100, height: 100)
        #expect(StudioBackground.imageRect(.zero, filling: picture) == .zero)
        #expect(StudioBackground.imageRect(CGSize(width: 0, height: 10), filling: picture) == .zero)
    }

    // MARK: Saved data

    @Test func everyKindRoundTrips() throws {
        let backgrounds: [StudioBackground] = [
            .screen, .color(.lightGray), .color(BackgroundColor(red: 0.25, green: 0.5, blue: 0.75)),
            .gradient(StudioBackground.gradients[1].gradient),
            .image(BackgroundImage(fileName: "Background.heic", name: "Beach.heic")),
        ]
        for background in backgrounds {
            #expect(try decoded(saved(background)) == background)
        }
    }

    @Test func aMissingOrUnreadableBackgroundIsTheScreen() throws {
        #expect(try decoded("{}") == .screen)
        #expect(try decoded("{\"background\": 3}") == .screen)
        #expect(try decoded("{\"background\": {\"pattern\": {}}}") == .screen)
        #expect(try decoded("{\"background\": {\"color\": {\"_0\": {\"red\": 1}}}}") == .screen)
    }

    @Test func anImageWithoutAFileNameOrWithAPathIsTheScreen() throws {
        #expect(try decoded(saved(.image(BackgroundImage(fileName: "", name: "a.png")))) == .screen)
        #expect(try decoded(saved(.image(BackgroundImage(fileName: "../a.png", name: "a.png")))) == .screen)
        #expect(try decoded(saved(.image(BackgroundImage(fileName: "a/b.png", name: "b.png")))) == .screen)
        #expect(try decoded(saved(.image(BackgroundImage(fileName: ".", name: "a.png")))) == .screen)
        #expect(try decoded(saved(.image(BackgroundImage(fileName: "..", name: "a.png")))) == .screen)
        // A name that merely starts with dots is a file name.
        let dotted = StudioBackground.image(BackgroundImage(fileName: "..a.png", name: "a.png"))
        #expect(try decoded(saved(dotted)) == dotted)
    }

    @Test func colourComponentsAreClampedToTheUnitRange() throws {
        let json = "{\"background\": {\"color\": {\"_0\": {\"red\": 1.5, \"green\": -0.2, \"blue\": 0.4}}}}"
        #expect(try decoded(json) == .color(BackgroundColor(red: 1, green: 0, blue: 0.4)))
    }

    @Test func gradientColoursAreClampedToo() throws {
        let json = """
            {"background": {"gradient": {"_0": {"top": {"red": 2, "green": 2, "blue": 2},
            "bottom": {"red": -1, "green": 0.5, "blue": 0}}}}}
            """
        #expect(
            try decoded(json)
                == .gradient(
                    BackgroundGradient(top: .white, bottom: BackgroundColor(red: 0, green: 0.5, blue: 0))))
    }

    @Test func clampingKeepsComponentsInTheUnitRange() {
        #expect(
            BackgroundColor(clampingRed: 1.2, green: -0.1, blue: 0.5) == BackgroundColor(red: 1, green: 0, blue: 0.5))
        #expect(BackgroundColor(clampingRed: 0, green: 1, blue: 0) == BackgroundColor(red: 0, green: 1, blue: 0))
    }

    @Test func eightBitComponentsMapOntoTheUnitRange() {
        #expect(BackgroundColor(255, 0, 51) == BackgroundColor(red: 1, green: 0, blue: 0.2))
    }
}
