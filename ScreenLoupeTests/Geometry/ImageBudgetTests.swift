import CoreGraphics
import Testing

struct ImageBudgetTests {
    @Test func anImageWithinTheBudgetStaysWhole() {
        #expect(ImageBudget.fitted(width: 4096, height: 4096) == (4096, 4096))
        #expect(ImageBudget.fitted(width: 1440, height: 9000) == (1440, 9000))
    }

    @Test func aHugeCopyKeepsItsTopLeft4096Square() {
        // A 400 × 300 px selection at 6400%.
        #expect(ImageBudget.fitted(width: 25600, height: 19200) == (4096, 4096))
    }

    @Test func aNarrowImageKeepsItsWidthAndLosesHeight() {
        #expect(ImageBudget.fitted(width: 1024, height: 20000) == (1024, 16384))
        #expect(ImageBudget.fitted(width: 2048, height: 12000) == (2048, 8192))
    }

    @Test func aWideShortImageKeepsItsHeightAndLosesWidth() {
        // A Viewer full screen on a 6K display.
        #expect(ImageBudget.fitted(width: 6016, height: 3384) == (4957, 3384))
    }

    @Test func noSideExceedsTheTextureLimit() {
        #expect(ImageBudget.fitted(width: 20000, height: 100) == (16384, 100))
    }

    @Test func sizesRoundToWholePixels() {
        #expect(ImageBudget.fitted(CGSize(width: 25600, height: 19200)) == CGSize(width: 4096, height: 4096))
        #expect(ImageBudget.fitted(CGSize(width: 99.6, height: 50.2)) == CGSize(width: 100, height: 50))
    }
}
