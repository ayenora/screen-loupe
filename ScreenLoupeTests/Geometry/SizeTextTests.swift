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
