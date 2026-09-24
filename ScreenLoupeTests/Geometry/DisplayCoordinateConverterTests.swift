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
}
