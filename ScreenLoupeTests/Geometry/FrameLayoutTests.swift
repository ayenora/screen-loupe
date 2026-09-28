import CoreGraphics
import Testing

struct FrameLayoutTests {
    @Test func aCapturedFrameIsTheAreaWithItsCapturedPartAndTheDisplaysScale() throws {
        let primary = DisplayInfo(id: 1, globalFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2)
        let right = DisplayInfo(id: 2, globalFrame: CGRect(x: 1440, y: -180, width: 1920, height: 1080), scale: 1)
        let converter = DisplayCoordinateConverter(layout: try #require(DisplayLayout(displays: [primary, right])))
        // 40 pt of the area lie on the primary display; the right one captures the rest at 1×.
        let area = GlobalRect(rect: CGRect(x: 1400, y: 100, width: 100, height: 100))
        let layout = try #require(converter.captureGeometry(for: area)).layout
        #expect(layout.size == PixelSize(width: 100, height: 100))
        #expect(layout.imageOrigin == CGPoint(x: 40, y: 0))
        #expect(layout.imageSize == PixelSize(width: 60, height: 100))
        #expect(layout.scale == 1)
    }

    @Test func aStillImageIsAllOfItAtOnePixelPerPoint() {
        let layout = FrameLayout(image: PixelSize(width: 640, height: 480))
        #expect(layout.size == PixelSize(width: 640, height: 480))
        #expect(layout.imageOrigin == .zero)
        #expect(layout.imageSize == PixelSize(width: 640, height: 480))
        #expect(layout.scale == 1)
        #expect(layout.imageRectInAreaImage == CGRect(x: 0, y: 0, width: 640, height: 480))
    }

    @Test func aStillImageFitsLikeACapture() {
        let layout = FrameLayout(image: PixelSize(width: 6016, height: 3384))
        #expect(layout.fittedToImageBudget() == FrameLayout(image: PixelSize(width: 4957, height: 3384)))
    }
}
