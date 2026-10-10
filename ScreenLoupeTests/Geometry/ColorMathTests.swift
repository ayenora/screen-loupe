import CoreGraphics
import Testing

struct ColorMathTests {
    let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    let displayP3 = CGColorSpace(name: CGColorSpace.displayP3)!

    @Test func sRGBPixelKeepsItsValues() {
        let sample = ColorSample(red: 24, green: 25, blue: 28, colorSpace: sRGB)
        #expect(sample.hex == "#18191C")
        #expect(sample.cssRGB == "rgb(24 25 28)")
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

    @Test func aColourOutsideSRGBKeepsItsExtendedValues() {
        // Display P3 red and green lie outside sRGB: clamped for HEX, beyond 0...1 in extended sRGB.
        let red = ColorSample(red: 255, green: 0, blue: 0, colorSpace: displayP3)
        #expect(red.srgb == (1, 0, 0))
        #expect(red.extendedSRGB.red > 1.05 && red.extendedSRGB.green < -0.05 && red.extendedSRGB.blue < -0.01)
        let green = ColorSample(red: 0, green: 255, blue: 0, colorSpace: displayP3)
        #expect(green.extendedSRGB.green > 1 && green.extendedSRGB.red < 0)
        #expect(green.hex == "#00FF00")
    }

    @Test func aColourInsideSRGBHasItsSRGBValuesExtended() {
        let sample = ColorSample(red: 58, green: 123, blue: 213, colorSpace: sRGB)
        #expect(abs(sample.extendedSRGB.red - sample.srgb.red) < 1e-6)
        #expect(abs(sample.extendedSRGB.green - sample.srgb.green) < 1e-6)
        #expect(abs(sample.extendedSRGB.blue - sample.srgb.blue) < 1e-6)
        let hex = ColorSample(srgbHex: "#3A7BD5")
        #expect(hex.extendedSRGB == hex.srgb)
    }

    @Test func anOpenedImageKeepsAnRGBSpaceAndGetsSRGBOtherwise() throws {
        #expect(CGColorSpace.rgbSpace(forImageIn: displayP3) == displayP3)
        #expect(CGColorSpace.rgbSpace(forImageIn: nil) == sRGB)
        let palette = try #require(CGColorSpace(indexedBaseSpace: displayP3, last: 0, colorTable: [255, 0, 0]))
        #expect(CGColorSpace.rgbSpace(forImageIn: palette) == displayP3)
        let gray = try #require(CGColorSpace(name: CGColorSpace.genericGrayGamma2_2))
        #expect(CGColorSpace.rgbSpace(forImageIn: gray) == sRGB)
        let cmyk = try #require(CGColorSpace(name: CGColorSpace.genericCMYK))
        #expect(CGColorSpace.rgbSpace(forImageIn: cmyk) == sRGB)
        let float = try #require(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
        #expect(CGColorSpace.rgbSpace(forImageIn: float) == sRGB)
    }

    @Test func aTranslucentPixelNamesItsOpacityInEveryFormat() {
        let sample = ColorSample(red: 255, green: 0, blue: 0, alpha: 128, colorSpace: sRGB)
        #expect(sample.hex == "#FF000080")
        #expect(sample.cssRGB == "rgb(255 0 0 / 0.502)")
        #expect(sample.swiftUI == "Color(red: 1.000, green: 0.000, blue: 0.000, opacity: 0.502)")
        #expect(sample.appKit == "NSColor(srgbRed: 1.000, green: 0.000, blue: 0.000, alpha: 0.502)")
        #expect(sample.nativeValues == "1.000 0.000 0.000")
        // A kept colour is kept by its HEX and comes back with its opacity.
        #expect(ColorSample(srgbHex: sample.hex) == ColorSample(srgbHex: "#FF000080"))
        #expect(ColorSample(srgbHex: sample.hex).alpha == sample.alpha)
        #expect(ColorSample(srgbHex: "#FF0000").alpha == 1)
    }

    @Test func formats() {
        let sample = ColorSample(srgbHex: "#0A6FE0")
        #expect(sample.hex == "#0A6FE0")
        #expect(sample.swiftUI == "Color(red: 0.039, green: 0.435, blue: 0.878)")
        #expect(sample.appKit == "NSColor(srgbRed: 0.039, green: 0.435, blue: 0.878, alpha: 1)")
    }

    @Test(arguments: [
        // Opaque: no opacity, whatever the alpha byte's rounding would print.
        (UInt8(58), UInt8(123), UInt8(213), UInt8(255), "rgb(58 123 213)"),
        (0, 0, 0, 255, "rgb(0 0 0)"),
        (255, 255, 255, 255, "rgb(255 255 255)"),
        // Translucent: the opacity after a slash, with three decimals, as SwiftUI and AppKit give it.
        (58, 123, 213, 128, "rgb(58 123 213 / 0.502)"),
        (58, 123, 213, 0, "rgb(58 123 213 / 0.000)"),
        (58, 123, 213, 1, "rgb(58 123 213 / 0.004)"),
        (58, 123, 213, 254, "rgb(58 123 213 / 0.996)"),
    ])
    func cssUsesTheSyntaxWithoutCommas(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8, expected: String) {
        #expect(ColorSample(red: red, green: green, blue: blue, alpha: alpha, colorSpace: sRGB).cssRGB == expected)
    }

    @Test func cssRoundsEachComponentToTheNearestByte() {
        // Just under and just over half a byte: the byte nearest to the value.
        let sample = ColorSample(
            native: (0, 0, 0), nativeSpaceName: "sRGB", srgb: (57.49 / 255, 122.51 / 255, 212.49 / 255), alpha: 0.5)
        #expect(sample.cssRGB == "rgb(57 123 212 / 0.500)")
    }

    @Test func theStandardFormatsAreTheRowsInOrder() {
        let sample = ColorSample(red: 58, green: 123, blue: 213, colorSpace: sRGB)
        #expect(ColorFormat.standard.map(\.title) == ["HEX", "CSS", "SwiftUI", "AppKit", "Native"])
        #expect(
            ColorFormat.standard.map { $0.text(sample, "native") } == [
                "#3A7BD5", "rgb(58 123 213)", "Color(red: 0.227, green: 0.482, blue: 0.835)",
                "NSColor(srgbRed: 0.227, green: 0.482, blue: 0.835, alpha: 1)", "native",
            ])
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
}
