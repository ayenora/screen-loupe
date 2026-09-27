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
        #expect(frame.width == CGFloat(1440 - 2 * (40 + 64 + 8)))
        #expect(frame.height == CGFloat(800 - 80))
        #expect(frame.midX == visible.midX)
        #expect(frame.minY == CGFloat(110))
        // The palette fits left of it.
        let origin = StudioPlacement.paletteOrigin(size: palette, beside: frame, in: visible)
        #expect(origin.x == frame.minX - 32 - 40)
        #expect(origin.x >= visible.minX + 8)
    }

    @Test func defaultFrameOnADisplayLeftOfThePrimary() {
        let visible = CGRect(x: -1920, y: 0, width: 1920, height: 1055)
        let frame = StudioPlacement.defaultFrame(in: visible, paletteWidth: 40)
        #expect(frame.size == CGSize(width: 1440, height: 900))
        #expect(frame.midX == visible.midX)
        #expect(visible.contains(frame))
    }

    @Test func paletteSitsLeftOfTheFrameTopAligned() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = CGRect(x: 300, y: 200, width: 600, height: 400)
        let origin = StudioPlacement.paletteOrigin(size: palette, beside: frame, in: visible)
        #expect(origin == CGPoint(x: 300 - 32 - 40, y: 380))
    }

    @Test func paletteGoesRightWhenThereIsNoRoomOnTheLeft() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = CGRect(x: 50, y: 200, width: 600, height: 400)
        let origin = StudioPlacement.paletteOrigin(size: palette, beside: frame, in: visible)
        #expect(origin.x == CGFloat(650 + 32))
    }

    @Test func paletteStaysOnTheDisplayWhenThereIsRoomOnNeitherSide() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = CGRect(x: 10, y: 0, width: 1420, height: 900)
        let origin = StudioPlacement.paletteOrigin(size: palette, beside: frame, in: visible)
        #expect(origin == CGPoint(x: 8, y: 900 - 8 - 220))
    }

    @Test func paletteIsKeptAboveTheDisplaysBottom() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = CGRect(x: 300, y: 20, width: 300, height: 100)
        let origin = StudioPlacement.paletteOrigin(size: palette, beside: frame, in: visible)
        #expect(origin.y == CGFloat(8))
    }

    @Test func paletteBesideAFrameOnADisplayWithNegativeCoordinates() {
        let visible = CGRect(x: -1920, y: -300, width: 1920, height: 1080)
        let frame = CGRect(x: -1500, y: -100, width: 800, height: 500)
        let origin = StudioPlacement.paletteOrigin(size: palette, beside: frame, in: visible)
        #expect(origin == CGPoint(x: -1500 - 32 - 40, y: 180))
        // At the display's left edge, the palette goes right, still on that display.
        let atEdge = CGRect(x: -1900, y: -100, width: 800, height: 500)
        let right = StudioPlacement.paletteOrigin(size: palette, beside: atEdge, in: visible)
        #expect(right.x == CGFloat(-1100 + 32))
        #expect(visible.contains(CGRect(origin: right, size: palette)))
    }

    @Test func paletteOriginIsInWholePointsBesideAFrameOnHalfPoints() {
        // A frame snapped to a 2× display's pixels can sit on half points; the palette doesn't.
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 944)
        let frame = CGRect(x: 300.5, y: 200.5, width: 600, height: 400)
        let origin = StudioPlacement.paletteOrigin(size: palette, beside: frame, in: visible)
        #expect(origin.x == origin.x.rounded())
        #expect(origin.y == origin.y.rounded())
        #expect(frame.minX - (origin.x + palette.width) >= StudioPlacement.paletteGap - 0.5)
    }

    // MARK: The frame's hover zone and position box

    @Test func paletteGapExceedsTheFramesHoverZone() {
        let metrics = OverlayMetrics.standard
        #expect(StudioPlacement.paletteGap > metrics.hoverReach)
        #expect(StudioPlacement.paletteGap > metrics.lineWidth + metrics.bandWidth + metrics.handleHitSize / 2)
    }

    /// The frame's layout with its position box keeping off `paletteRect`.
    private func frameLayout(_ frame: CGRect, on display: CGRect, avoiding paletteRect: CGRect) -> OverlayLayout {
        OverlayLayout(
            captureRect: frame, screenFrame: display, tabWidth: 180, labelWidth: 60,
            positionSize: CGSize(width: 90, height: 70), positionAvoiding: paletteRect, lockButtons: false)
    }

    /// Points along `rect`'s edges, every 2 pt, and its centre.
    private func points(of rect: CGRect) -> [CGPoint] {
        var points = [CGPoint(x: rect.midX, y: rect.midY)]
        for y in stride(from: rect.minY, through: rect.maxY, by: 2) {
            points += [CGPoint(x: rect.minX, y: y), CGPoint(x: rect.maxX, y: y)]
        }
        for x in stride(from: rect.minX, through: rect.maxX, by: 2) {
            points += [CGPoint(x: x, y: rect.minY), CGPoint(x: x, y: rect.maxY)]
        }
        return points
    }

    @Test(arguments: [
        // Left of the frame, on the primary display.
        (CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 300, y: 200, width: 600, height: 400)),
        // Right of it: no room on the left.
        (CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 40, y: 200, width: 600, height: 400)),
        // Left of a frame at the display's right edge, where the box has no room on the right.
        (CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1000, y: 200, width: 432, height: 400)),
        // A display left of and below the primary.
        (CGRect(x: -1920, y: -300, width: 1920, height: 1080), CGRect(x: -1500, y: -100, width: 800, height: 500)),
    ])
    func pointerOnThePaletteNeverRevealsTheFrameNorItsBox(display: CGRect, frame: CGRect) {
        let origin = StudioPlacement.paletteOrigin(size: palette, beside: frame, in: display)
        let paletteRect = CGRect(origin: origin, size: palette)
        let layout = frameLayout(frame, on: display, avoiding: paletteRect)
        #expect(!layout.positionRect.intersects(paletteRect))
        #expect(!layout.positionRect.intersects(frame))
        #expect(!points(of: paletteRect).contains { layout.isInHoverZone($0) })
    }

    // MARK: The Size list

    @Test func sizeListSitsRightOfThePaletteLevelWithTheButton() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let palette = CGRect(x: 800, y: 400, width: 40, height: 300)
        let origin = StudioPlacement.popoverOrigin(
            size: CGSize(width: 240, height: 320), beside: palette, anchorTop: 600, in: visible)
        #expect(origin == CGPoint(x: 846, y: 280))
    }

    @Test func sizeListGoesLeftAtTheDisplaysRightEdge() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let palette = CGRect(x: 1390, y: 400, width: 40, height: 300)
        let origin = StudioPlacement.popoverOrigin(
            size: CGSize(width: 240, height: 320), beside: palette, anchorTop: 600, in: visible)
        #expect(origin.x == CGFloat(1390 - 6 - 240))
    }

    @Test func sizeListStaysOnTheDisplayVertically() {
        let visible = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        let palette = CGRect(x: -1000, y: -190, width: 40, height: 300)
        let size = CGSize(width: 240, height: 320)
        // Near the bottom: lifted to the margin.
        let low = StudioPlacement.popoverOrigin(size: size, beside: palette, anchorTop: -100, in: visible)
        #expect(low == CGPoint(x: -954, y: -192))
        // Above the top: lowered to the margin.
        let high = StudioPlacement.popoverOrigin(size: size, beside: palette, anchorTop: 2000, in: visible)
        #expect(high.y == CGFloat(880 - 8 - 320))
    }

    // MARK: Hover labels

    private let display = CGRect(x: 0, y: 0, width: 1440, height: 900)

    @Test func hoverLabelGoesLeftWithTheFrameRightOfThePalette() {
        let palette = CGRect(x: 200, y: 300, width: 36, height: 500)
        let frame = CGRect(x: 268, y: 200, width: 800, height: 600)
        let x = StudioPlacement.hoverLabelX(width: 90, beside: palette, frame: frame, in: display)
        #expect(x == CGFloat(200 - 6 - 90))
    }

    @Test func hoverLabelGoesRightWithTheFrameLeftOfThePalette() {
        let palette = CGRect(x: 900, y: 300, width: 36, height: 500)
        let frame = CGRect(x: 60, y: 200, width: 808, height: 600)
        let x = StudioPlacement.hoverLabelX(width: 90, beside: palette, frame: frame, in: display)
        #expect(x == CGFloat(936 + 6))
    }

    @Test func hoverLabelGoesTowardsTheFrameWithThePaletteAtTheDisplaysEdge() {
        let frame = CGRect(x: 76, y: 200, width: 800, height: 600)
        let atLeft = CGRect(x: 8, y: 300, width: 36, height: 500)
        #expect(StudioPlacement.hoverLabelX(width: 90, beside: atLeft, frame: frame, in: display) == CGFloat(44 + 6))
        let farFrame = CGRect(x: 300, y: 200, width: 800, height: 600)
        let atRight = CGRect(x: 1396, y: 300, width: 36, height: 500)
        #expect(
            StudioPlacement.hoverLabelX(width: 90, beside: atRight, frame: farFrame, in: display)
                == CGFloat(1396 - 6 - 90))
    }

    @Test func hoverLabelWithoutAFrameGoesRightOrLeftAtTheEdge() {
        let palette = CGRect(x: 200, y: 300, width: 36, height: 500)
        #expect(StudioPlacement.hoverLabelX(width: 90, beside: palette, frame: nil, in: display) == CGFloat(242))
        let atRight = CGRect(x: 1396, y: 300, width: 36, height: 500)
        #expect(StudioPlacement.hoverLabelX(width: 90, beside: atRight, frame: nil, in: display) == CGFloat(1300))
    }

    @Test func hoverLabelOnADisplayWithNegativeCoordinates() {
        let visible = CGRect(x: -1920, y: -300, width: 1920, height: 1080)
        let frame = CGRect(x: -1500, y: -100, width: 800, height: 500)
        let left = CGRect(x: -1568, y: 0, width: 36, height: 400)
        #expect(StudioPlacement.hoverLabelX(width: 90, beside: left, frame: frame, in: visible) == CGFloat(-1664))
        let atEdge = CGRect(x: -1912, y: 0, width: 36, height: 400)
        #expect(
            StudioPlacement.hoverLabelX(width: 90, beside: atEdge, frame: frame, in: visible) == CGFloat(-1870))
    }
}
