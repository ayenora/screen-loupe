import CoreGraphics
import Testing

struct PixelDensityTests {
    static let multiples: [(Double, Int)] = [(72, 1), (144, 2), (216, 3)]

    @Test(arguments: multiples)
    func wholeMultiplesOf72(dpi: Double, pixelsPerPoint: Int) {
        #expect(PixelDensity.pixelsPerPoint(dpiWidth: dpi, dpiHeight: dpi) == pixelsPerPoint)
    }

    @Test func noResolutionIsUnknown() {
        #expect(PixelDensity.pixelsPerPoint(dpiWidth: nil, dpiHeight: nil) == nil)
    }

    @Test func oneSideIsEnough() {
        #expect(PixelDensity.pixelsPerPoint(dpiWidth: 144, dpiHeight: nil) == 2)
        #expect(PixelDensity.pixelsPerPoint(dpiWidth: nil, dpiHeight: 216) == 3)
    }

    /// Other resolutions — a Windows default, print, a fraction of 2× — say nothing about a screen.
    static let odd: [Double] = [96, 300, 150, 108, 36, 288, 360, 720, 1]

    @Test(arguments: odd)
    func otherResolutionsAreUnknown(dpi: Double) {
        #expect(PixelDensity.pixelsPerPoint(dpiWidth: dpi, dpiHeight: dpi) == nil)
    }

    /// PNG keeps pixels per metre: 72 ppi is stored as 2835, which reads back as 72.009.
    @Test func aResolutionStoredPerMetreStillCounts() {
        #expect(PixelDensity.pixelsPerPoint(dpiWidth: 2835 * 0.0254, dpiHeight: 2835 * 0.0254) == 1)
        #expect(PixelDensity.pixelsPerPoint(dpiWidth: 5669 * 0.0254, dpiHeight: 5669 * 0.0254) == 2)
        #expect(PixelDensity.pixelsPerPoint(dpiWidth: 143.4, dpiHeight: 143.4) == nil)
    }

    @Test func differentSidesAreUnknown() {
        #expect(PixelDensity.pixelsPerPoint(dpiWidth: 144, dpiHeight: 72) == nil)
        #expect(PixelDensity.pixelsPerPoint(dpiWidth: 72, dpiHeight: 216) == nil)
        // Within rounding, the same.
        #expect(PixelDensity.pixelsPerPoint(dpiWidth: 144, dpiHeight: 144.3) == 2)
    }

    static let invalid: [Double] = [0, -72, -144, .infinity, -.infinity, .nan]

    @Test(arguments: invalid)
    func zeroNegativeAndNonFiniteAreUnknown(dpi: Double) {
        #expect(PixelDensity.pixelsPerPoint(dpiWidth: dpi, dpiHeight: dpi) == nil)
        #expect(PixelDensity.pixelsPerPoint(dpiWidth: dpi, dpiHeight: nil) == nil)
    }

    @Test func anInvalidSideBesideAGoodOneIsUnknown() {
        #expect(PixelDensity.pixelsPerPoint(dpiWidth: 0, dpiHeight: 144) == nil)
        #expect(PixelDensity.pixelsPerPoint(dpiWidth: 144, dpiHeight: .nan) == nil)
    }

    // MARK: The display's scale

    @Test func theStreamsDisplayComesFirst() {
        #expect(PixelDensity.sourceScale(stream: 2, area: 1) == 2)
        #expect(PixelDensity.sourceScale(stream: 1, area: nil) == 1)
    }

    /// The stream starting, or moving to another display: the area's display, which it is about to capture.
    @Test func withoutAStreamTheAreasDisplay() {
        #expect(PixelDensity.sourceScale(stream: nil, area: 2) == 2)
        #expect(PixelDensity.sourceScale(stream: nil, area: 3) == 3)
    }

    /// Neither known: the layer keeps one image pixel per source pixel.
    @Test func neitherKnownKeepsPixelForPixel() {
        let scale = PixelDensity.sourceScale(stream: nil, area: nil)
        #expect(scale == nil)
        #expect(PixelDensity.referenceScale(pixelsPerPoint: 2, sourceScale: scale) == 1)
    }

    // MARK: The layer's scale

    @Test func aRetinaDisplay() {
        #expect(PixelDensity.referenceScale(pixelsPerPoint: 2, sourceScale: 2) == 1)
        #expect(PixelDensity.referenceScale(pixelsPerPoint: 1, sourceScale: 2) == 2)
        #expect(PixelDensity.referenceScale(pixelsPerPoint: 3, sourceScale: 2) == CGFloat(2) / 3)
    }

    @Test func aStandardDisplay() {
        #expect(PixelDensity.referenceScale(pixelsPerPoint: 1, sourceScale: 1) == 1)
        #expect(PixelDensity.referenceScale(pixelsPerPoint: 2, sourceScale: 1) == 0.5)
    }

    @Test func aThreeTimesDisplay() {
        #expect(PixelDensity.referenceScale(pixelsPerPoint: 3, sourceScale: 3) == 1)
        #expect(PixelDensity.referenceScale(pixelsPerPoint: 1, sourceScale: 3) == 3)
    }

    /// Without a density or a display, one image pixel per source pixel, as a dropped file.
    @Test func anUnknownKeepsPixelForPixel() {
        #expect(PixelDensity.referenceScale(pixelsPerPoint: nil, sourceScale: 2) == 1)
        #expect(PixelDensity.referenceScale(pixelsPerPoint: 2, sourceScale: nil) == 1)
        #expect(PixelDensity.referenceScale(pixelsPerPoint: nil, sourceScale: nil) == 1)
    }

    @Test func anInvalidScaleKeepsPixelForPixel() {
        #expect(PixelDensity.referenceScale(pixelsPerPoint: 2, sourceScale: 0) == 1)
        #expect(PixelDensity.referenceScale(pixelsPerPoint: 2, sourceScale: -2) == 1)
        #expect(PixelDensity.referenceScale(pixelsPerPoint: 2, sourceScale: .infinity) == 1)
        #expect(PixelDensity.referenceScale(pixelsPerPoint: 0, sourceScale: 2) == 1)
    }

    /// Every scale it gives is one a layer can have.
    @Test func theScaleStaysInTheLayerRange() {
        for density in PixelDensity.pixelsPerPointRange {
            for display in [1, 2, 3] as [CGFloat] {
                let scale = PixelDensity.referenceScale(pixelsPerPoint: density, sourceScale: display)
                #expect(ReferenceStack.scaleRange.contains(scale))
            }
        }
    }
}
