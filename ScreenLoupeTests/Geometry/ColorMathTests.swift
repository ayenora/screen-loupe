import CoreGraphics
import Testing

struct ColorMathTests {
    let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    let displayP3 = CGColorSpace(name: CGColorSpace.displayP3)!

    @Test func sRGBPixelKeepsItsValues() {
        let sample = ColorSample(red: 24, green: 25, blue: 28, colorSpace: sRGB)
        #expect(sample.hex == "#18191C")
        #expect(sample.cssRGB == "rgb(24, 25, 28)")
        #expect(sample.nativeSpaceName == "sRGB")
    }

    @Test func displayP3PixelIsConvertedToSRGB() {
        // P3 red is outside sRGB: its sRGB value clips to pure red.
        let red = ColorSample(red: 255, green: 0, blue: 0, colorSpace: displayP3)
        #expect(red.hex == "#FF0000")
        #expect(red.nativeSpaceName == "Display P3")
        #expect(red.nativeValues == "1.000 0.000 0.000")
        // Mid grey is the same in both spaces (same transfer curve and white point).
        let grey = ColorSample(red: 128, green: 128, blue: 128, colorSpace: displayP3)
        #expect(grey.hex == "#808080")
    }

    @Test func formats() {
        let sample = ColorSample(srgbHex: "#0A6FE0")
        #expect(sample.hex == "#0A6FE0")
        #expect(sample.swiftUI == "Color(red: 0.039, green: 0.435, blue: 0.878)")
        #expect(sample.appKit == "NSColor(srgbRed: 0.039, green: 0.435, blue: 0.878, alpha: 1)")
    }

    @Test(arguments: [
        ("#FFFFFF", "#000000", 21.0),
        ("#FFFFFF", "#FFFFFF", 1.0),
        // WCAG's own reference pair: #767676 on white is 4.54:1.
        ("#FFFFFF", "#767676", 4.54),
    ])
    func contrastRatio(a: String, b: String, expected: Double) {
        let ratio = ColorSample.contrastRatio(ColorSample(srgbHex: a), ColorSample(srgbHex: b))
        #expect(abs(ratio - expected) < 0.01)
    }

    @Test func ratingThresholds() {
        let rating = ContrastRating(ratio: 4.6)
        #expect(rating.passesAA)
        #expect(!rating.passesAAA)
        #expect(rating.passesAALarge)
        #expect(rating.text == "4.60 : 1")
    }
}
