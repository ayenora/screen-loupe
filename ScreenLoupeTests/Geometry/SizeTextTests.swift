import CoreGraphics
import Testing

struct SizeTextTests {
    @Test(arguments: [
        (CGSize(width: 220, height: 150), "220 × 150"),
        (CGSize(width: 120.5, height: 80), "120.5 × 80"),
        (CGSize(width: 99.99999, height: 0.5), "100 × 0.5"),
    ])
    func points(size: CGSize, expected: String) {
        #expect(SizeText.points(size) == expected)
    }

    @Test func pointsAndPixelsOnRetina() {
        #expect(
            SizeText.pointsAndPixels(CGSize(width: 220, height: 150.5), scale: 2) == "220 × 150.5 pt · 440 × 301 px")
    }

    @Test(arguments: [
        (CGFloat(2), "32 px · 16 pt"),
        (CGFloat(3), "32 px · 10.7 pt"),
        (CGFloat(1.5), "32 px · 21.3 pt"),
        (CGFloat(1), "32 px"),
    ])
    func pairGivesBothUnlessAPixelIsAPoint(scale: CGFloat, expected: String) {
        #expect(SizeText.pair("32 px", "\(RulerLabel.points(32 / scale)) pt", scale: scale) == expected)
    }

    @Test func pairKeepsTheFirstOrTheSecondWhereAPixelIsAPoint() {
        #expect(SizeText.pair("16 pt", "16 px", scale: 1) == "16 pt")
        #expect(SizeText.pair("16 pt", "16 px", scale: 1, keepsSecond: true) == "16 px")
        // Only where they are equal: elsewhere both, in their order.
        #expect(SizeText.pair("16 pt", "32 px", scale: 2, keepsSecond: true) == "16 pt · 32 px")
    }

    @Test func pointsAndPixelsOnA1xDisplayIsOneSize() {
        let size = CGSize(width: 294, height: 240)
        #expect(SizeText.pointsAndPixels(size, scale: 1) == "294 × 240 pt")
        #expect(SizeText.pointsAndPixels(size, scale: 1, keepsPixels: true) == "294 × 240 px")
    }

    @Test func pointsAndPixelsAt3x() {
        #expect(
            SizeText.pointsAndPixels(CGSize(width: 100, height: 33.3333), scale: 3) == "100 × 33.3 pt · 300 × 100 px")
    }

    @Test(arguments: [
        // Units, the Capture Area's tab, the studio frame's tab (sizes in pixels).
        (SizeUnits.pointsAndPixels, "294 × 240 pt", "294 × 240 px"),
        (SizeUnits.points, "294 × 240 pt", "294 × 240 pt"),
        (SizeUnits.pixels, "294 × 240 px", "294 × 240 px"),
    ])
    func tabOnA1xDisplay(units: SizeUnits, captureArea: String, studio: String) {
        let size = CGSize(width: 294, height: 240)
        #expect(SizeText.tab(size, scale: 1, units: units) == captureArea)
        #expect(SizeText.tab(size, scale: 1, units: units, keepsPixels: true) == studio)
        #expect(SizeText.label(size, scale: 1, units: units) == "294 × 240")
    }

    @Test func theStudioTabGivesBothOnARetinaDisplay() {
        #expect(
            SizeText.tab(CGSize(width: 1440, height: 900), scale: 2, units: .pointsAndPixels, keepsPixels: true)
                == "1440 × 900 pt · 2880 × 1800 px")
    }

    @Test(arguments: [
        (SizeUnits.pointsAndPixels, "220 × 150 pt · 440 × 300 px", "220 × 150"),
        (SizeUnits.points, "220 × 150 pt", "220 × 150"),
        (SizeUnits.pixels, "440 × 300 px", "440 × 300"),
    ])
    func units(units: SizeUnits, tab: String, label: String) {
        let size = CGSize(width: 220, height: 150)
        #expect(SizeText.tab(size, scale: 2, units: units) == tab)
        #expect(SizeText.label(size, scale: 2, units: units) == label)
    }

    @Test func edgesAreLeftTopRightBottomInPointsOrPixels() {
        let rect = CGRect(x: 209, y: 149.5, width: 222, height: 152)
        #expect(SizeText.edges(rect, scale: 2, units: .points).map(\.value) == ["209", "149.5", "431", "301.5"])
        #expect(SizeText.edges(rect, scale: 2, units: .pixels).map(\.value) == ["418", "299", "862", "603"])
        #expect(SizeText.edges(rect, scale: 2, units: .pointsAndPixels).map(\.key) == ["L", "T", "R", "B"])
    }
}
