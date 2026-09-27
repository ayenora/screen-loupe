import CoreGraphics
import Testing

struct FrameTabColorsTests {
    let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    private func tab(_ red: Int, _ green: Int, _ blue: Int) -> FrameTabColors {
        FrameTabColors(accentRed: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
    }

    /// The accent at `factor`, as the tab's fill.
    private func expected(_ red: Int, _ green: Int, _ blue: Int, _ factor: Double, white: Bool) -> FrameTabColors {
        var colors = tab(0, 0, 0)
        (colors.red, colors.green, colors.blue) = (
            Double(red) / 255 * factor, Double(green) / 255 * factor, Double(blue) / 255 * factor
        )
        colors.textIsWhite = white
        return colors
    }

    private func whiteContrast(_ colors: FrameTabColors) -> Double {
        func byte(_ value: Double) -> UInt8 { UInt8((value * 255).rounded()) }
        let fill = ColorSample(
            red: byte(colors.red), green: byte(colors.green), blue: byte(colors.blue), colorSpace: sRGB)
        return ColorSample.contrastRatio(fill, ColorSample(red: 255, green: 255, blue: 255, colorSpace: sRGB))
    }

    @Test func everyCaptureAreaPresetKeepsItsTabAndText() {
        // Blue, orange, pink, purple: white on the accent at 78%.
        #expect(tab(10, 132, 255) == expected(10, 132, 255, 0.78, white: true))
        #expect(tab(255, 107, 0) == expected(255, 107, 0, 0.78, white: true))
        #expect(tab(255, 55, 95) == expected(255, 55, 95, 0.78, white: true))
        #expect(tab(191, 90, 242) == expected(191, 90, 242, 0.78, white: true))
        // Amber, green, white: black on the accent at 78%.
        #expect(tab(255, 159, 10) == expected(255, 159, 10, 0.78, white: false))
        #expect(tab(48, 209, 88) == expected(48, 209, 88, 0.78, white: false))
        #expect(tab(255, 255, 255) == expected(255, 255, 255, 0.78, white: false))
    }

    @Test func orangePresetIsWhiteRightAtTheThreshold() {
        // (199, 83, 0): white 4.50:1 at 78%, so its tab isn't darkened.
        let colors = tab(255, 107, 0)
        #expect(colors.textIsWhite)
        #expect(whiteContrast(colors) >= 4.5)
        #expect(whiteContrast(colors) < 4.51)
    }

    @Test func studioOrangeGetsWhiteOnADarkerTab() {
        // At 78% (187, 99, 20) white is 4.28:1 and black 4.91:1; at 74% (178, 94, 19) white is 4.66:1.
        let colors = tab(240, 127, 26)
        #expect(colors.textIsWhite)
        #expect(whiteContrast(colors) >= 4.5)
        #expect(abs(colors.red - 240.0 / 255 * 0.74) < 1e-9)
        #expect(abs(colors.green - 127.0 / 255 * 0.74) < 1e-9)
        #expect(abs(colors.blue - 26.0 / 255 * 0.74) < 1e-9)
    }

    @Test func darkeningStopsAtTheFirstStepThatReachesWhite() {
        // Grey 169: 3.74 at 78%, 3.95, 4.12, 4.29, then 4.54:1 at 70%, the floor.
        let colors = tab(169, 169, 169)
        #expect(colors.textIsWhite)
        #expect(abs(colors.red - 169.0 / 255 * 0.70) < 1e-9)
        #expect(whiteContrast(colors) >= 4.5)
    }

    @Test func accentThatNoStepMakesReadableInWhiteGetsBlack() {
        // Grey 170: 4.48:1 at 70%, short of 4.5, so black on the 78% tab.
        #expect(tab(170, 170, 170) == expected(170, 170, 170, 0.78, white: false))
    }

    @Test func blackAccentGetsWhiteAndWhiteAccentGetsBlack() {
        #expect(tab(0, 0, 0) == expected(0, 0, 0, 0.78, white: true))
        #expect(tab(255, 255, 255) == expected(255, 255, 255, 0.78, white: false))
    }
}
