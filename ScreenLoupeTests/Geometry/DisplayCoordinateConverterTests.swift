import CoreGraphics
import Testing

/// A mixed layout: a 2× primary, a 1× display to its right hanging 180 pt lower, a large 1× display
/// to its left reaching higher, and a 2× display stacked above it.
private enum Fixture {
    static let primary = DisplayInfo(id: 1, globalFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2)
    static let right = DisplayInfo(id: 2, globalFrame: CGRect(x: 1440, y: -180, width: 1920, height: 1080), scale: 1)
    static let left = DisplayInfo(id: 3, globalFrame: CGRect(x: -2560, y: 0, width: 2560, height: 1440), scale: 1)
    static let above = DisplayInfo(id: 4, globalFrame: CGRect(x: 0, y: 900, width: 1512, height: 982), scale: 2)

    static let converter: DisplayCoordinateConverter = {
        guard let layout = DisplayLayout(displays: [right, primary, left, above]) else {
            fatalError("Fixture layout has a primary display")
        }
        return DisplayCoordinateConverter(layout: layout)
    }()
}

struct DisplayLayoutTests {
    @Test func primaryIsTheDisplayAtTheOrigin() throws {
        let layout = try #require(DisplayLayout(displays: [Fixture.right, Fixture.primary]))
        #expect(layout.primary == Fixture.primary)
    }

    @Test func layoutWithoutADisplayAtTheOriginIsRejected() {
        #expect(DisplayLayout(displays: [Fixture.right, Fixture.left]) == nil)
    }
}

struct DisplayCoordinateConverterTests {
    let converter = Fixture.converter

    @Test func globalToQuartzFlipsAroundThePrimaryDisplay() {
        let quartz = converter.quartzRect(GlobalRect(rect: CGRect(x: 100, y: 100, width: 200, height: 100)))
        #expect(quartz.rect == CGRect(x: 100, y: 700, width: 200, height: 100))
    }

    @Test(arguments: [
        CGRect(x: 100, y: 100, width: 200, height: 100),
        CGRect(x: -2000, y: 1000, width: 100, height: 100),
        CGRect(x: 1500, y: -150, width: 33, height: 17),
        CGRect(x: 10.5, y: 1800.5, width: 50, height: 40),
    ])
    func quartzRoundTripsToGlobal(rect: CGRect) {
        let global = GlobalRect(rect: rect)
        #expect(converter.globalRect(converter.quartzRect(global)) == global)
    }

    @Test(arguments: [
        // Primary: the top-left of the primary display is the Quartz origin.
        (
            CGRect(x: 100, y: 100, width: 200, height: 100), Fixture.primary,
            CGRect(x: 100, y: 700, width: 200, height: 100)
        ),
        // Right display, tops aligned with the primary.
        (CGRect(x: 1500, y: 0, width: 100, height: 50), Fixture.right, CGRect(x: 60, y: 850, width: 100, height: 50)),
        // Left display: negative global x, top 540 pt above the primary's top.
        (
            CGRect(x: -2000, y: 1000, width: 100, height: 100), Fixture.left,
            CGRect(x: 560, y: 340, width: 100, height: 100)
        ),
        // Display stacked above the primary: negative Quartz y.
        (CGRect(x: 10, y: 1800, width: 50, height: 40), Fixture.above, CGRect(x: 10, y: 42, width: 50, height: 40)),
    ])
    func displayLocalRectIsRelativeToTheDisplaysTopLeft(global: CGRect, display: DisplayInfo, expected: CGRect) {
        let local = converter.displayLocalRect(GlobalRect(rect: global), on: display)
        #expect(local.displayID == display.id)
        #expect(local.rect == expected)
    }

    @Test(arguments: [
        (CGRect(x: 100, y: 100, width: 10, height: 10), Fixture.primary.id),
        (CGRect(x: -100, y: 100, width: 10, height: 10), Fixture.left.id),
        (CGRect(x: 100, y: 1000, width: 10, height: 10), Fixture.above.id),
        // Straddles primary (40 pt) and right (60 pt): the larger share wins.
        (CGRect(x: 1400, y: 100, width: 100, height: 100), Fixture.right.id),
        // Straddles primary (60 pt) and right (40 pt).
        (CGRect(x: 1380, y: 100, width: 100, height: 100), Fixture.primary.id),
    ])
    func owningDisplayHoldsTheLargestShare(rect: CGRect, expected: CGDirectDisplayID) {
        #expect(converter.owningDisplay(for: GlobalRect(rect: rect))?.id == expected)
    }

    @Test func rectOnNoDisplayHasNoOwner() {
        let offScreen = GlobalRect(rect: CGRect(x: 5000, y: 5000, width: 10, height: 10))
        #expect(converter.owningDisplay(for: offScreen) == nil)
        #expect(converter.captureGeometry(for: offScreen) == nil)
    }

    @Test(arguments: [
        // 2×: steps of 0.5 pt. Origin and size round independently.
        (CGRect(x: 10.2, y: 20.3, width: 100.1, height: 50.26), CGRect(x: 10, y: 20.5, width: 100, height: 50.5)),
        (CGRect(x: 10.25, y: 20.75, width: 100.75, height: 50), CGRect(x: 10.5, y: 21, width: 101, height: 50)),
        // 1×: whole points.
        (CGRect(x: 1500.4, y: 10.6, width: 99.5, height: 20.2), CGRect(x: 1500, y: 11, width: 100, height: 20)),
    ])
    func snappingAlignsToTheOwningDisplaysPixelGrid(rect: CGRect, expected: CGRect) {
        #expect(converter.snapped(GlobalRect(rect: rect)).rect == expected)
    }

    @Test func edgeSnappingRoundsEachEdgeOnItsOwn() {
        let snapped = converter.snappedEdges(GlobalRect(rect: CGRect(x: 10.2, y: 20.3, width: 100.1, height: 50.26)))
        #expect(snapped.rect == CGRect(x: 10, y: 20.5, width: 100.5, height: 50))
    }

    @Test func snappingKeepsTheSizeWhileMoving() {
        let size = CGSize(width: 120.5, height: 80)
        for step in 0..<20 {
            let x = 10 + CGFloat(step) * 0.37
            let snapped = converter.snapped(GlobalRect(rect: CGRect(origin: CGPoint(x: x, y: 10), size: size)))
            #expect(snapped.rect.size == size)
        }
    }

    @Test(arguments: [
        // 1×: the top-left point is pixel (0, 0); y grows downwards from the top edge.
        (CGPoint(x: 100, y: 199.5), CGFloat(1), 0, 0),
        (CGPoint(x: 150.2, y: 150), CGFloat(1), 50, 50),
        // 2×: every point is two pixels.
        (CGPoint(x: 100.75, y: 199.9), CGFloat(2), 1, 0),
        (CGPoint(x: 299.9, y: 100.1), CGFloat(2), 399, 199),
    ])
    func areaPixelUnderAGlobalPoint(point: CGPoint, scale: CGFloat, x: Int, y: Int) throws {
        let area = CGRect(x: 100, y: 100, width: 200, height: 100)
        let pixel = try #require(DisplayCoordinateConverter.areaPixel(at: point, inArea: area, scale: scale))
        #expect(pixel.x == x)
        #expect(pixel.y == y)
    }

    @Test func noAreaPixelOutsideTheArea() {
        let area = CGRect(x: 100, y: 100, width: 200, height: 100)
        #expect(DisplayCoordinateConverter.areaPixel(at: CGPoint(x: 99, y: 150), inArea: area, scale: 2) == nil)
        #expect(DisplayCoordinateConverter.areaPixel(at: CGPoint(x: 150, y: 200.5), inArea: area, scale: 2) == nil)
    }

    @Test func retinaCaptureOutputsBackingPixels() throws {
        let area = GlobalRect(rect: CGRect(x: 100.5, y: 200, width: 300, height: 150))
        let geometry = try #require(converter.captureGeometry(for: area))
        #expect(geometry.display == Fixture.primary)
        #expect(geometry.sourceRect.rect == CGRect(x: 100.5, y: 550, width: 300, height: 150))
        #expect(geometry.outputSize == PixelSize(width: 600, height: 300))
        #expect(geometry.areaSize == PixelSize(width: 600, height: 300))
        #expect(geometry.imageOrigin == .zero)
    }

    @Test func straddlingAreaCapturesTheVisiblePartAndPlacesItInTheArea() throws {
        // 40 pt on the primary, 60 pt on the right display, which wins.
        let area = GlobalRect(rect: CGRect(x: 1400, y: 100, width: 100, height: 100))
        let geometry = try #require(converter.captureGeometry(for: area))
        #expect(geometry.display == Fixture.right)
        #expect(geometry.sourceRect.rect == CGRect(x: 0, y: 700, width: 60, height: 100))
        #expect(geometry.outputSize == PixelSize(width: 60, height: 100))
        #expect(geometry.areaSize == PixelSize(width: 100, height: 100))
        #expect(geometry.imageOrigin == CGPoint(x: 40, y: 0))
    }

    @Test func areaHangingOffTheTopOfADisplayIsOffsetVertically() throws {
        // The above display's top edge is at global y 1882; 10 pt of the area sticks out above it.
        let area = GlobalRect(rect: CGRect(x: 100, y: 1842, width: 50, height: 50))
        let geometry = try #require(converter.captureGeometry(for: area))
        #expect(geometry.display == Fixture.above)
        #expect(geometry.sourceRect.rect == CGRect(x: 100, y: 0, width: 50, height: 40))
        #expect(geometry.outputSize == PixelSize(width: 100, height: 80))
        #expect(geometry.areaSize == PixelSize(width: 100, height: 100))
        #expect(geometry.imageOrigin == CGPoint(x: 0, y: 20))
    }

    @Test func areaOriginCountsFromTheCapturingDisplaysTopLeft() throws {
        // 40 pt of the area lie left of the right display, which captures it at 1×.
        let area = GlobalRect(rect: CGRect(x: 1400, y: 100, width: 100, height: 100))
        let geometry = try #require(converter.captureGeometry(for: area))
        #expect(geometry.areaOrigin == CGPoint(x: -40, y: 700))
    }

    @Test(arguments: [
        // Straddling the primary and the right display: the image is the right part.
        (CGRect(x: 1400, y: 100, width: 100, height: 100), CGRect(x: 40, y: 0, width: 60, height: 100)),
        // Hanging off the top of the display above: the image is the lower part, at the bottom in y-up.
        (CGRect(x: 100, y: 1842, width: 50, height: 50), CGRect(x: 0, y: 0, width: 100, height: 80)),
        // Hanging off the bottom of the primary: the image is the upper part.
        (CGRect(x: 100, y: -10, width: 50, height: 50), CGRect(x: 0, y: 20, width: 100, height: 80)),
    ])
    func capturedImageSitsInTheAreaImage(area: CGRect, expected: CGRect) throws {
        let geometry = try #require(converter.captureGeometry(for: GlobalRect(rect: area)))
        #expect(geometry.imageRectInAreaImage == expected)
    }
}

struct AreaResizeTrackerTests {
    let converter = Fixture.converter
    let start = CGRect(x: 100, y: 100, width: 200, height: 100)

    private func shift(from first: CGRect, to second: CGRect, forgetting: Bool = false) throws -> CGPoint {
        var tracker = AreaResizeTracker()
        _ = tracker.originShift(for: try #require(converter.captureGeometry(for: GlobalRect(rect: first))))
        if forgetting { tracker.forget() }
        return tracker.originShift(for: try #require(converter.captureGeometry(for: GlobalRect(rect: second))))
    }

    @Test func aMoveKeepsTheFraming() throws {
        #expect(try shift(from: start, to: start.offsetBy(dx: 10, dy: -5)) == .zero)
    }

    @Test func dragsOfTheRightOrBottomEdgeKeepTheFraming() throws {
        #expect(try shift(from: start, to: CGRect(x: 100, y: 100, width: 210, height: 100)) == .zero)
        #expect(try shift(from: start, to: CGRect(x: 100, y: 90, width: 200, height: 110)) == .zero)
    }

    @Test func dragsOfTheLeftOrTopEdgeShiftTheOriginInPixels() throws {
        // The primary is 2×: 10 pt are 20 px. Global y is up, so the top edge is `maxY`.
        #expect(try shift(from: start, to: CGRect(x: 90, y: 100, width: 210, height: 100)) == CGPoint(x: -20, y: 0))
        #expect(try shift(from: start, to: CGRect(x: 100, y: 100, width: 200, height: 110)) == CGPoint(x: 0, y: -20))
    }

    @Test func aResizeOnAnotherDisplayKeepsTheFraming() throws {
        #expect(try shift(from: start, to: CGRect(x: -500, y: 100, width: 150, height: 100)) == .zero)
    }

    @Test func afterForgettingAResizeKeepsTheFraming() throws {
        #expect(try shift(from: start, to: CGRect(x: 90, y: 100, width: 210, height: 100), forgetting: true) == .zero)
    }
}
