import CoreGraphics
import Testing

/// A 2× primary; a 1× display to its left, reaching higher (negative Quartz y); a 3× display above
/// the primary (negative Quartz y); and a 2× display right of the primary hanging lower.
private enum Fixture {
    static let primary = DisplayInfo(id: 1, globalFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2)
    static let left = DisplayInfo(id: 2, globalFrame: CGRect(x: -2560, y: 0, width: 2560, height: 1440), scale: 1)
    static let above = DisplayInfo(id: 3, globalFrame: CGRect(x: 0, y: 900, width: 1200, height: 800), scale: 3)
    static let right = DisplayInfo(id: 4, globalFrame: CGRect(x: 1440, y: -300, width: 1512, height: 982), scale: 2)
    static let displays = [primary, left, above, right]

    static let converter: DisplayCoordinateConverter = {
        guard let layout = DisplayLayout(displays: displays) else {
            fatalError("Fixture layout has a primary display")
        }
        return DisplayCoordinateConverter(layout: layout)
    }()
}

struct ScreenshotRequestTests {
    let converter = Fixture.converter

    private func request(_ area: CGRect) throws -> (CaptureGeometry, ScreenshotRequest) {
        let geometry = try #require(converter.captureGeometry(for: GlobalRect(rect: area)))
        return (geometry, converter.screenshotRequest(for: geometry))
    }

    // MARK: Whole points

    @Test func wholePointsAreAskedForAsTheyAre() throws {
        let (_, request) = try request(CGRect(x: 100, y: 100, width: 200, height: 100))
        #expect(request.rect.rect == CGRect(x: 100, y: 700, width: 200, height: 100))
        #expect(request.pictureSize == PixelSize(width: 400, height: 200))
        #expect(request.crop == PixelRect(x: 0, y: 0, width: 400, height: 200))
    }

    @Test func theWholeDisplayIsTheDisplaysQuartzFrame() throws {
        let (_, request) = try request(Fixture.primary.globalFrame)
        #expect(request.rect.rect == CGRect(x: 0, y: 0, width: 1440, height: 900))
        #expect(request.pictureSize == PixelSize(width: 2880, height: 1800))
        #expect(request.crop == PixelRect(x: 0, y: 0, width: 2880, height: 1800))
    }

    // MARK: Pixels between points

    @Test func aHalfPointOriginOnRetinaIsGrownToWholePointsAndCutBack() throws {
        // x 100.5 is pixel 201; 401 px wide, the last pixel ends at 602 px, 301 pt.
        let (geometry, request) = try request(CGRect(x: 100.5, y: 100, width: 200.5, height: 100))
        #expect(geometry.outputSize == PixelSize(width: 401, height: 200))
        #expect(request.rect.rect == CGRect(x: 100, y: 700, width: 201, height: 100))
        #expect(request.pictureSize == PixelSize(width: 402, height: 200))
        #expect(request.crop == PixelRect(x: 1, y: 0, width: 401, height: 200))
    }

    @Test func aHalfPointTopOnRetinaIsCutFromTheTop() throws {
        // Global y up: a top edge at 200.5 is Quartz y 699.5, pixel 1399 of the display.
        let (_, request) = try request(CGRect(x: 100, y: 100, width: 200, height: 100.5))
        #expect(request.rect.rect == CGRect(x: 100, y: 699, width: 200, height: 101))
        #expect(request.pictureSize == PixelSize(width: 400, height: 202))
        #expect(request.crop == PixelRect(x: 0, y: 1, width: 400, height: 201))
    }

    @Test func aFractionalOriginOnRetinaIsGrownOnBothSides() throws {
        // As a rect at the mouse's location: 200 × 200 pt from (100.3, 100.3), y up.
        let (geometry, request) = try request(CGRect(x: 100.3, y: 100.3, width: 200, height: 200))
        #expect(geometry.outputSize == PixelSize(width: 400, height: 400))
        // Quartz y 599.7: pixel 1199, the picture starting at 599 pt.
        #expect(request.rect.rect == CGRect(x: 100, y: 599, width: 201, height: 201))
        #expect(request.pictureSize == PixelSize(width: 402, height: 402))
        #expect(request.crop == PixelRect(x: 1, y: 1, width: 400, height: 400))
    }

    @Test func aFractionalRectAtOneTimesIsRoundedToItsPixels() throws {
        // On the left display: 1 px is 1 pt, so the pixels the stream gives are whole points already.
        let (geometry, request) = try request(CGRect(x: -2000.4, y: 1000.3, width: 100.6, height: 50.2))
        #expect(geometry.display == Fixture.left)
        #expect(geometry.outputSize == PixelSize(width: 101, height: 50))
        let width = CGFloat(request.pictureSize.width)
        let height = CGFloat(request.pictureSize.height)
        #expect(request.rect.rect.size == CGSize(width: width, height: height))
        #expect(request.crop == PixelRect(x: 0, y: 0, width: 101, height: 50))
    }

    @Test func aThirdOfAPointAtThreeTimes() throws {
        // x 10 + 1/3 is pixel 31; 60 px end at pixel 91, in point 31.
        let (geometry, request) = try request(CGRect(x: 10 + 1.0 / 3, y: 1000, width: 20, height: 20))
        #expect(geometry.display == Fixture.above)
        #expect(geometry.outputSize == PixelSize(width: 60, height: 60))
        #expect(request.rect.rect.minX == CGFloat(10))
        #expect(request.rect.rect.width == CGFloat(21))
        #expect(request.pictureSize.width == 63)
        #expect(request.crop.x == 1)
        #expect(request.crop.width == 60)
    }

    @Test func twoThirdsOfAPointAtThreeTimesCutTwoPixels() throws {
        let (_, request) = try request(CGRect(x: 10 + 2.0 / 3, y: 1000, width: 20, height: 20))
        // Pixel 32: point 10, two pixels in; 60 px end at pixel 92, in point 31.
        #expect(request.rect.rect.minX == CGFloat(10))
        #expect(request.rect.rect.width == CGFloat(21))
        #expect(request.crop.x == 2)
    }

    // MARK: Displays with negative origins

    @Test func aDisplayLeftOfThePrimaryHasNegativeQuartzCoordinates() throws {
        // Its top is 540 pt above the primary's: Quartz y −540.
        let (_, request) = try request(CGRect(x: -2000, y: 1000, width: 100, height: 100))
        #expect(request.rect.rect == CGRect(x: -2000, y: -200, width: 100, height: 100))
        #expect(request.pictureSize == PixelSize(width: 100, height: 100))
        #expect(request.crop == PixelRect(x: 0, y: 0, width: 100, height: 100))
    }

    @Test func aDisplayAboveThePrimaryAtThreeTimes() throws {
        // The above display's top is Quartz y −800; the area's top is 100 pt below it.
        let (_, request) = try request(CGRect(x: 50, y: 1500, width: 100, height: 100))
        #expect(request.rect.rect == CGRect(x: 50, y: -700, width: 100, height: 100))
        #expect(request.pictureSize == PixelSize(width: 300, height: 300))
    }

    @Test func aDisplayHangingBelowThePrimary() throws {
        // The right display's top is Quartz y 218 (900 − 682); a half point on its 2× grid.
        let (geometry, request) = try request(CGRect(x: 1500.5, y: 0, width: 100, height: 100))
        #expect(geometry.display == Fixture.right)
        #expect(request.rect.rect == CGRect(x: 1500, y: 800, width: 101, height: 100))
        #expect(request.crop == PixelRect(x: 1, y: 0, width: 200, height: 200))
    }

    // MARK: For any rect

    private static let fractions: [CGFloat] = [0, 0.1, 0.25, 1.0 / 3, 0.4, 0.5, 0.6, 2.0 / 3, 0.75, 0.9]

    /// Areas inside each display with every fraction of a point at the origin and in the size.
    private func everyArea() -> [CGRect] {
        Fixture.displays.flatMap { display in
            Self.fractions.flatMap { origin in
                Self.fractions.map { size in
                    CGRect(
                        x: display.globalFrame.minX + 37 + origin, y: display.globalFrame.minY + 23 + origin,
                        width: 211 + size, height: 97 + size)
                }
            }
        }
    }

    @Test func theRectIsWholePointsAndThePictureItsPixels() throws {
        for area in everyArea() {
            let (geometry, request) = try request(area)
            let rect = request.rect.rect
            #expect(rect.minX == rect.minX.rounded() && rect.minY == rect.minY.rounded(), "\(area)")
            #expect(rect.width == rect.width.rounded() && rect.height == rect.height.rounded(), "\(area)")
            let scale = geometry.display.scale
            #expect(
                request.pictureSize
                    == PixelSize(width: Int(rect.width * scale), height: Int(rect.height * scale)), "\(area)")
        }
    }

    @Test func theCropIsTheStreamsPixelsInsideThePicture() throws {
        for area in everyArea() {
            let (geometry, request) = try request(area)
            let crop = request.crop
            #expect(crop.size == geometry.outputSize, "\(area)")
            #expect(crop.x >= 0 && crop.y >= 0, "\(area)")
            #expect(crop.x + crop.width <= request.pictureSize.width, "\(area)")
            #expect(crop.y + crop.height <= request.pictureSize.height, "\(area)")
            // Less than a point of spare pixels on each side.
            let scale = Int(geometry.display.scale)
            #expect(crop.x < scale && crop.y < scale, "\(area)")
            #expect(request.pictureSize.width - crop.x - crop.width < scale, "\(area)")
            #expect(request.pictureSize.height - crop.y - crop.height < scale, "\(area)")
        }
    }

    @Test func theCropStartsOnThePixelTheStreamStartsOn() throws {
        for area in everyArea() {
            let (geometry, request) = try request(area)
            let scale = geometry.display.scale
            let display = converter.quartzRect(GlobalRect(rect: geometry.display.globalFrame)).rect
            let x = (request.rect.rect.minX - display.minX) * scale + CGFloat(request.crop.x)
            let y = (request.rect.rect.minY - display.minY) * scale + CGFloat(request.crop.y)
            #expect(x == (geometry.sourceRect.rect.minX * scale).rounded(), "\(area)")
            #expect(y == (geometry.sourceRect.rect.minY * scale).rounded(), "\(area)")
        }
    }

    @Test func theRectStaysOnItsDisplay() throws {
        for display in Fixture.displays {
            // Each corner, a fraction of a point in from the display's edges.
            let frame = display.globalFrame
            for area in [
                CGRect(x: frame.minX + 0.4, y: frame.minY + 0.4, width: 100, height: 100),
                CGRect(x: frame.maxX - 100.4, y: frame.maxY - 100.4, width: 100, height: 100),
                frame,
            ] {
                let (_, request) = try request(area)
                let quartz = converter.quartzRect(GlobalRect(rect: frame)).rect
                #expect(quartz.contains(request.rect.rect), "\(area)")
            }
        }
    }
}
