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
}
