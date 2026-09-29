import CoreGraphics
import Foundation
import Testing

struct CaptureAreaResetTests {
    /// Every coordinate is a whole number of pixels at `scale`.
    private func isOnGrid(_ rect: CGRect, scale: CGFloat) -> Bool {
        [rect.minX, rect.minY, rect.width, rect.height].allSatisfy { abs(($0 * scale).rounded() - $0 * scale) < 1e-9 }
    }

    @Test func theDefaultSizeIsTheFirstLaunchSize() {
        #expect(CaptureAreaReset.defaultSize == CGSize(width: 320, height: 200))
    }

    @Test func aNonRetinaDisplayCentresTheDefaultSizeOnWholePoints() {
        // The menu bar leaves 1055 of 1080: the centre falls on a half point, which rounds.
        let visible = CGRect(x: 0, y: 0, width: 1920, height: 1055)
        let rect = CaptureAreaReset.rect(centredIn: visible, scale: 1)
        #expect(rect == CGRect(x: 800, y: 428, width: 320, height: 200))
    }

    @Test func aRetinaDisplayKeepsAHalfPointOrigin() {
        // A half point is a whole pixel at 2×.
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 949)
        let rect = CaptureAreaReset.rect(centredIn: visible, scale: 2)
        #expect(rect == CGRect(x: 596, y: 374.5, width: 320, height: 200))
        #expect(isOnGrid(rect, scale: 2))
    }

    @Test func aDisplayLeftOfThePrimaryGivesANegativeOrigin() {
        let visible = CGRect(x: -1920, y: -300, width: 1920, height: 1080)
        let rect = CaptureAreaReset.rect(centredIn: visible, scale: 1)
        #expect(rect == CGRect(x: -1120, y: 140, width: 320, height: 200))
    }

    @Test func aNegativeHalfPointCentreRoundsOntoTheGrid() {
        let visible = CGRect(x: -1281, y: -801, width: 1281, height: 801)
        let rect = CaptureAreaReset.rect(centredIn: visible, scale: 1)
        #expect(isOnGrid(rect, scale: 1))
        #expect(rect.size == CaptureAreaReset.defaultSize)
        #expect(abs(rect.midX - visible.midX) <= 0.5)
        #expect(abs(rect.midY - visible.midY) <= 0.5)
    }

    @Test func aDisplayAboveThePrimaryCentresOnIt() {
        let visible = CGRect(x: 200, y: 1080, width: 2560, height: 1415)
        let rect = CaptureAreaReset.rect(centredIn: visible, scale: 2)
        #expect(rect == CGRect(x: 1320, y: 1687.5, width: 320, height: 200))
    }

    @Test func aDisplaySmallerThanTheDefaultSizeGetsItsWholeVisibleFrame() {
        let visible = CGRect(x: -300, y: 40, width: 300, height: 150)
        #expect(CaptureAreaReset.rect(centredIn: visible, scale: 1) == visible)
        #expect(CaptureAreaReset.rect(centredIn: visible, scale: 2) == visible)
    }

    @Test func onlyTheSideThatDoesNotFitShrinks() {
        let visible = CGRect(x: 100, y: 0, width: 1000, height: 150)
        let rect = CaptureAreaReset.rect(centredIn: visible, scale: 1)
        #expect(rect == CGRect(x: 440, y: 0, width: 320, height: 150))
    }

    @Test func aShrunkSideStaysOnWholePixels() {
        // A visible height between two pixels at 2× takes the whole pixels that fit.
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 150.25)
        let rect = CaptureAreaReset.rect(centredIn: visible, scale: 2)
        #expect(rect.height == CGFloat(150))
        #expect(isOnGrid(rect, scale: 2))
        #expect(visible.contains(rect))
    }

    @Test func anotherSizeIsCentredTheSameWay() {
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let rect = CaptureAreaReset.rect(centredIn: visible, scale: 1, size: CGSize(width: 101, height: 51))
        #expect(rect == CGRect(x: 450, y: 375, width: 101, height: 51))
    }

    @Test func theRectAlwaysLiesOnItsVisibleFrameOnTheGrid() {
        let frames = [
            CGRect(x: 0, y: 0, width: 1440, height: 875),
            CGRect(x: -1728, y: -1117, width: 1728, height: 1084),
            CGRect(x: 3008, y: 25, width: 1025, height: 767),
            CGRect(x: 0, y: 0, width: 319, height: 199),
        ]
        for visible in frames {
            for scale in [CGFloat(1), 2, 3] {
                let rect = CaptureAreaReset.rect(centredIn: visible, scale: scale)
                #expect(visible.contains(rect), "\(visible) at \(scale)×")
                #expect(isOnGrid(rect, scale: scale), "\(visible) at \(scale)×")
            }
        }
    }
}
