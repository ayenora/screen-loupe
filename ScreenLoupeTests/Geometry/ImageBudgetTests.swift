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

    private func geometry(area: PixelSize, output: PixelSize, imageOrigin: CGPoint = .zero) -> CaptureGeometry {
        CaptureGeometry(
            display: DisplayInfo(id: 1, globalFrame: CGRect(x: 0, y: 0, width: 3008, height: 1692), scale: 2),
            sourceRect: DisplayLocalRect(displayID: 1, rect: CGRect(x: 0, y: 0, width: 100, height: 100)),
            outputSize: output, areaSize: area, imageOrigin: imageOrigin)
    }

    @Test func aCaptureWithinTheBudgetIsKeptWhole() {
        let small = geometry(area: PixelSize(width: 880, height: 540), output: PixelSize(width: 880, height: 540))
        #expect(small.fittedToImageBudget() == small)
    }

    @Test func aHugeCaptureKeepsTheTopLeftOfItsArea() {
        // A whole 6K display.
        let whole = geometry(area: PixelSize(width: 6016, height: 3384), output: PixelSize(width: 6016, height: 3384))
        let kept = whole.fittedToImageBudget()
        #expect(kept?.areaSize == PixelSize(width: 4957, height: 3384))
        #expect(kept?.outputSize == PixelSize(width: 4957, height: 3384))
        #expect(kept?.imageOrigin == .zero)
    }

    @Test func aStraddlingCaptureKeepsItsImageWhereItIs() {
        // 1000 px of the area lie on the other display, left of the captured image.
        let straddling = geometry(
            area: PixelSize(width: 6000, height: 3000), output: PixelSize(width: 5000, height: 3000),
            imageOrigin: CGPoint(x: 1000, y: 0))
        let kept = straddling.fittedToImageBudget()
        #expect(kept?.areaSize == PixelSize(width: 5592, height: 3000))
        #expect(kept?.outputSize == PixelSize(width: 4592, height: 3000))
        #expect(kept?.imageOrigin == CGPoint(x: 1000, y: 0))
    }

    @Test func aCaptureWhoseImageLiesPastTheBudgetKeepsNothing() {
        let straddling = geometry(
            area: PixelSize(width: 9000, height: 4096), output: PixelSize(width: 4000, height: 4096),
            imageOrigin: CGPoint(x: 5000, y: 0))
        #expect(straddling.fittedToImageBudget() == nil)
    }

    @Test func sizesRoundToWholePixels() {
        #expect(ImageBudget.fitted(CGSize(width: 25600, height: 19200)) == CGSize(width: 4096, height: 4096))
        #expect(ImageBudget.fitted(CGSize(width: 99.6, height: 50.2)) == CGSize(width: 100, height: 50))
    }
}
