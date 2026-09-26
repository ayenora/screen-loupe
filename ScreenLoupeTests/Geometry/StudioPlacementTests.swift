import CoreGraphics
import Testing

struct StudioPlacementTests {
    private let palette = CGSize(width: 40, height: 220)

    @Test func defaultFrameIsCentredAtItsSizeOnALargeDisplay() {
        let visible = CGRect(x: 0, y: 0, width: 2560, height: 1415)
        let frame = StudioPlacement.defaultFrame(in: visible, paletteWidth: 40)
        #expect(frame.size == CGSize(width: 1440, height: 900))
        #expect(frame.origin == CGPoint(x: 560, y: 257))
    }

    @Test func defaultFrameShrinksToLeaveRoomForThePaletteAndTheTab() {
        // A 1440 × 900 pt display, menu bar and Dock taken off.
        let visible = CGRect(x: 0, y: 70, width: 1440, height: 800)
        let frame = StudioPlacement.defaultFrame(in: visible, paletteWidth: 40)
        #expect(frame.width == CGFloat(1440 - 2 * (40 + 32 + 8)))
        #expect(frame.height == CGFloat(800 - 80))
        #expect(frame.midX == visible.midX)
        #expect(frame.minY == CGFloat(110))
        // The palette fits beside it.
        let origin = StudioPlacement.paletteOrigin(size: palette, beside: frame, in: visible)
        #expect(origin.x == frame.maxX + 16)
        #expect(origin.x + palette.width <= visible.maxX - 8)
    }

    @Test func defaultFrameOnADisplayLeftOfThePrimary() {
        let visible = CGRect(x: -1920, y: 0, width: 1920, height: 1055)
        let frame = StudioPlacement.defaultFrame(in: visible, paletteWidth: 40)
        #expect(frame.size == CGSize(width: 1440, height: 900))
        #expect(frame.midX == visible.midX)
        #expect(visible.contains(frame))
    }

    @Test func paletteSitsRightOfTheFrameTopAligned() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = CGRect(x: 100, y: 200, width: 600, height: 400)
        let origin = StudioPlacement.paletteOrigin(size: palette, beside: frame, in: visible)
        #expect(origin == CGPoint(x: 716, y: 380))
    }

    @Test func paletteGoesLeftWhenThereIsNoRoomOnTheRight() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = CGRect(x: 800, y: 200, width: 600, height: 400)
        let origin = StudioPlacement.paletteOrigin(size: palette, beside: frame, in: visible)
        #expect(origin.x == CGFloat(800 - 16 - 40))
    }

    @Test func paletteStaysOnTheDisplayWhenThereIsRoomOnNeitherSide() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = CGRect(x: 10, y: 0, width: 1420, height: 900)
        let origin = StudioPlacement.paletteOrigin(size: palette, beside: frame, in: visible)
        #expect(origin == CGPoint(x: 1440 - 8 - 40, y: 900 - 8 - 220))
    }

    @Test func paletteIsKeptAboveTheDisplaysBottom() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = CGRect(x: 100, y: 20, width: 300, height: 100)
        let origin = StudioPlacement.paletteOrigin(size: palette, beside: frame, in: visible)
        #expect(origin.y == CGFloat(8))
    }

    @Test func paletteBesideAFrameOnADisplayWithNegativeCoordinates() {
        let visible = CGRect(x: -1920, y: -300, width: 1920, height: 1080)
        let frame = CGRect(x: -1500, y: -100, width: 800, height: 500)
        let origin = StudioPlacement.paletteOrigin(size: palette, beside: frame, in: visible)
        #expect(origin == CGPoint(x: -684, y: 180))
    }
}
