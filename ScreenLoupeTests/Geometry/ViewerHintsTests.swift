import CoreGraphics
import Testing

/// A 400 × 300 pt image area.
struct ViewerHintsTests {
    private let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)

    @Test func aPillPadsItsTextOnWholePoints() {
        #expect(ViewerHints.pillSize(textSize: CGSize(width: 100.2, height: 14.3)) == CGSize(width: 125, height: 27))
    }

    @Test func oneHintSitsCentredAboveTheBottom() {
        let rects = ViewerHints.rects(sizes: [CGSize(width: 200, height: 26)], in: bounds)
        #expect(rects == [CGRect(x: 100, y: 254, width: 200, height: 26)])
    }

    @Test func aSecondHintStacksAboveTheFirstWithoutOverlapping() {
        let rects = ViewerHints.rects(
            sizes: [CGSize(width: 300, height: 26), CGSize(width: 180, height: 26)], in: bounds)
        #expect(rects[0] == CGRect(x: 50, y: 254, width: 300, height: 26))
        #expect(rects[1] == CGRect(x: 110, y: 220, width: 180, height: 26))
        #expect(!rects[0].intersects(rects[1]))
        #expect(rects[0].minY - rects[1].maxY == ViewerHints.spacing)
    }

    @Test func pillsSitOnWholePointsInAnOddArea() {
        let rects = ViewerHints.rects(
            sizes: [CGSize(width: 125, height: 27), CGSize(width: 99, height: 27)],
            in: CGRect(x: 0, y: 0, width: 401, height: 301.5))
        for rect in rects {
            #expect(rect.minX == rect.minX.rounded())
            #expect(rect.minY == rect.minY.rounded())
        }
        #expect(!rects[0].intersects(rects[1]))
    }

    @Test func noHintsNoPills() {
        #expect(ViewerHints.rects(sizes: [], in: bounds).isEmpty)
    }
}
