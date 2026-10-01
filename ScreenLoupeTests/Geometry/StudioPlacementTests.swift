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

    @Test func restoredPaletteInsideTheDisplayStaysWhereItWas() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let saved = CGPoint(x: 100, y: 300)
        #expect(StudioPlacement.restoredPaletteOrigin(saved, size: palette, in: visible) == saved)
        // Touching every edge exactly is inside: no margin is added.
        let corner = CGPoint(x: 1440 - 40, y: 875 - 220)
        #expect(StudioPlacement.restoredPaletteOrigin(corner, size: palette, in: visible) == corner)
        #expect(StudioPlacement.restoredPaletteOrigin(.zero, size: palette, in: visible) == .zero)
    }

    @Test func restoredPaletteThatGrewUpUnderTheMenuBarMovesDownJustEnough() {
        // Parked against the menu bar, 196 pt tall; now 220 pt, its top 24 pt above the visible frame.
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let saved = CGPoint(x: 600, y: 875 - 196)
        let origin = StudioPlacement.restoredPaletteOrigin(saved, size: palette, in: visible)
        #expect(origin == CGPoint(x: 600, y: 875 - 220))
    }

    @Test func restoredPaletteStickingOutAtAnySideComesBackOn() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let left = StudioPlacement.restoredPaletteOrigin(CGPoint(x: -15, y: 300), size: palette, in: visible)
        #expect(left == CGPoint(x: 0, y: 300))
        let right = StudioPlacement.restoredPaletteOrigin(CGPoint(x: 1420, y: 300), size: palette, in: visible)
        #expect(right == CGPoint(x: 1400, y: 300))
        // Below the visible frame: over the Dock.
        let bottom = StudioPlacement.restoredPaletteOrigin(CGPoint(x: 100, y: -50), size: palette, in: visible)
        #expect(bottom == CGPoint(x: 100, y: 0))
        let corner = StudioPlacement.restoredPaletteOrigin(CGPoint(x: 1430, y: 870), size: palette, in: visible)
        #expect(corner == CGPoint(x: 1400, y: 655))
    }

    @Test func restoredPaletteOnADisplayWithNegativeCoordinates() {
        let visible = CGRect(x: -1920, y: -300, width: 1920, height: 1055)
        let saved = CGPoint(x: -1930, y: 600)
        let origin = StudioPlacement.restoredPaletteOrigin(saved, size: palette, in: visible)
        #expect(origin == CGPoint(x: -1920, y: 755 - 220))
        #expect(visible.contains(CGRect(origin: origin, size: palette)))
    }

    @Test func restoredPaletteLargerThanTheDisplayKeepsItsTopLeftOn() {
        let visible = CGRect(x: 0, y: 0, width: 30, height: 200)
        let origin = StudioPlacement.restoredPaletteOrigin(CGPoint(x: 50, y: 100), size: palette, in: visible)
        #expect(origin == CGPoint(x: 0, y: 200 - 220))
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

    // MARK: The palette window

    /// The palette as a titled window on macOS 26: 36 pt buttons with 8 pt margins, eleven buttons in
    /// three groups 8 pt apart, and a 24 pt title bar on top.
    private let window = CGSize(width: 52, height: 24 + 8 + 11 * 36 + 2 * 8 + 8)

    @Test func paletteWidthAddsTheMarginOnBothSides() {
        #expect(StudioPlacement.paletteMargin > 0)
        #expect(StudioPlacement.paletteWidth(buttonWidth: 36) == 36 + 2 * StudioPlacement.paletteMargin)
        #expect(StudioPlacement.paletteWidth(buttonWidth: 32) == CGFloat(48))
        #expect(StudioPlacement.paletteWidth(buttonWidth: 0) == 2 * StudioPlacement.paletteMargin)
    }

    @Test func thePaletteIsAsWideAsOneWindowWithItsMenuButton() {
        // The widest row (`PaletteMenuButton.rowWidth`): 58 pt from macOS 26, 52 before.
        #expect(StudioPlacement.paletteWidth(buttonWidth: 58) == CGFloat(74))
        #expect(StudioPlacement.paletteWidth(buttonWidth: 52) == CGFloat(68))
    }

    @Test func defaultFrameLeavesRoomForThePaletteWindowOnA1440PointDisplay() {
        let visible = CGRect(x: 0, y: 70, width: 1440, height: 800)
        let frame = StudioPlacement.defaultFrame(
            in: visible, paletteWidth: StudioPlacement.paletteWidth(buttonWidth: 36))
        #expect(frame.width == CGFloat(1440 - 2 * (52 + 64 + 8)))
        let origin = StudioPlacement.paletteOrigin(size: window, beside: frame, in: visible)
        #expect(origin.x == frame.minX - 32 - 52)
        #expect(visible.contains(CGRect(origin: origin, size: window)))
    }

    @Test func paletteWindowsTitleBarIsLevelWithTheFramesTop() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = CGRect(x: 300, y: 200, width: 600, height: 500)
        let origin = StudioPlacement.paletteOrigin(size: window, beside: frame, in: visible)
        // The window's top, its title bar's, not the buttons' top.
        #expect(origin.y + window.height == frame.maxY)
        #expect(origin.x + window.width + StudioPlacement.paletteGap == frame.minX)
    }

    @Test func paletteWindowTallerThanTheRoomUnderTheFramesTopIsKeptOnTheDisplay() {
        // A frame low on a short display: the window's bottom would leave the display.
        let visible = CGRect(x: 0, y: 0, width: 1280, height: 600)
        let frame = CGRect(x: 400, y: 20, width: 400, height: 300)
        let origin = StudioPlacement.paletteOrigin(size: window, beside: frame, in: visible)
        #expect(origin.y == CGFloat(8))
        // Taller than the display: its title bar stays on it, the bottom goes off.
        let short = CGRect(x: 0, y: 0, width: 1280, height: 400)
        let top = StudioPlacement.paletteOrigin(size: window, beside: frame, in: short)
        #expect(top.y + window.height == CGFloat(400 - 8))
    }

    @Test(arguments: [
        (CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 300, y: 200, width: 600, height: 400)),
        (CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 40, y: 200, width: 600, height: 600)),
        (CGRect(x: -1920, y: -300, width: 1920, height: 1080), CGRect(x: -1500, y: -100, width: 800, height: 500)),
    ])
    func pointerOnThePaletteWindowNeverRevealsTheFrameNorItsBox(display: CGRect, frame: CGRect) {
        let origin = StudioPlacement.paletteOrigin(size: window, beside: frame, in: display)
        let paletteRect = CGRect(origin: origin, size: window)
        let layout = frameLayout(frame, on: display, avoiding: paletteRect)
        #expect(!layout.positionRect.intersects(paletteRect))
        #expect(!points(of: paletteRect).contains { layout.isInHoverZone($0) })
    }

    @Test func menusAndLabelsGoBesideThePaletteWindow() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let paletteRect = CGRect(origin: CGPoint(x: 600, y: 300), size: window)
        let frame = CGRect(x: 700, y: 200, width: 600, height: 600)
        let menu = StudioPlacement.menuTopLeft(
            size: CGSize(width: 240, height: 320), beside: paletteRect, anchorTop: 700, frame: frame, in: visible)
        #expect(menu.x + 240 + StudioPlacement.menuGap == paletteRect.minX)
        let label = StudioPlacement.hoverLabelX(width: 90, beside: paletteRect, frame: frame, in: visible)
        #expect(label + 90 + StudioPlacement.hoverLabelGap == paletteRect.minX)
    }

    // MARK: The palette's menus

    private let menuSize = CGSize(width: 240, height: 320)
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    @Test func aMenuGoesAwayFromTheFrameRightOfThePalette() {
        // The palette left of the frame: the menu opens on its left, its top level with the button.
        let palette = CGRect(x: 400, y: 400, width: 74, height: 300)
        let frame = CGRect(x: 520, y: 100, width: 800, height: 700)
        #expect(
            StudioPlacement.menuTopLeft(size: menuSize, beside: palette, anchorTop: 600, frame: frame, in: screen)
                == CGPoint(x: 400 - 6 - 240, y: 600))
    }

    @Test func aMenuGoesAwayFromTheFrameLeftOfThePalette() {
        let palette = CGRect(x: 1000, y: 400, width: 74, height: 300)
        let frame = CGRect(x: 100, y: 100, width: 850, height: 700)
        #expect(
            StudioPlacement.menuTopLeft(size: menuSize, beside: palette, anchorTop: 600, frame: frame, in: screen)
                == CGPoint(x: 1080, y: 600))
    }

    @Test func aMenuWithoutAFrameGoesRight() {
        let palette = CGRect(x: 400, y: 400, width: 74, height: 300)
        #expect(
            StudioPlacement.menuTopLeft(size: menuSize, beside: palette, anchorTop: 600, frame: nil, in: screen).x
                == CGFloat(480))
    }

    @Test func aMenuGoesTowardsTheFrameWithoutRoomAwayFromIt() {
        // The palette at the display's left edge, the frame right of it: no room on the left.
        let palette = CGRect(x: 8, y: 400, width: 74, height: 300)
        let frame = CGRect(x: 120, y: 100, width: 800, height: 700)
        #expect(
            StudioPlacement.menuTopLeft(size: menuSize, beside: palette, anchorTop: 600, frame: frame, in: screen).x
                == CGFloat(88))
        // At the right edge, the frame left of it: no room on the right.
        let atRight = CGRect(x: 1358, y: 400, width: 74, height: 300)
        let frameLeft = CGRect(x: 100, y: 100, width: 1200, height: 700)
        #expect(
            StudioPlacement.menuTopLeft(
                size: menuSize, beside: atRight, anchorTop: 600, frame: frameLeft, in: screen
            ).x == CGFloat(1358 - 6 - 240))
    }

    @Test func aMenuFittingExactlyStaysOnItsSide() {
        // 246 pt left of the palette: exactly the gap and the menu.
        let palette = CGRect(x: 246, y: 400, width: 74, height: 300)
        let frame = CGRect(x: 400, y: 100, width: 800, height: 700)
        #expect(
            StudioPlacement.menuTopLeft(size: menuSize, beside: palette, anchorTop: 600, frame: frame, in: screen).x
                == CGFloat(0))
        // One point less: to the right, towards the frame.
        let tight = CGRect(x: 245, y: 400, width: 74, height: 300)
        #expect(
            StudioPlacement.menuTopLeft(size: menuSize, beside: tight, anchorTop: 600, frame: frame, in: screen).x
                == CGFloat(325))
    }

    @Test func withRoomOnNeitherSideTheMenuStaysAwayFromTheFrame() {
        // A display barely wider than the palette: the system moves the menu on screen.
        let narrow = CGRect(x: 0, y: 0, width: 300, height: 900)
        let palette = CGRect(x: 100, y: 400, width: 74, height: 300)
        let frame = CGRect(x: 200, y: 100, width: 90, height: 700)
        #expect(
            StudioPlacement.menuTopLeft(size: menuSize, beside: palette, anchorTop: 600, frame: frame, in: narrow).x
                == CGFloat(100 - 6 - 240))
    }

    @Test func theMenusTopIsTheButtonsTopEvenNearTheDisplaysEdge() {
        // Left to the system, which moves a menu that would leave the screen.
        let palette = CGRect(x: 400, y: 10, width: 74, height: 300)
        for top: CGFloat in [40, 899, 2000, -50] {
            #expect(
                StudioPlacement.menuTopLeft(size: menuSize, beside: palette, anchorTop: top, frame: nil, in: screen).y
                    == top)
        }
    }

    @Test func aMenuOnADisplayWithNegativeCoordinatesAndHalfPoints() {
        let visible = CGRect(x: -1920, y: -300, width: 1920, height: 1080)
        let palette = CGRect(x: -1000.5, y: -100, width: 74, height: 300)
        let frame = CGRect(x: -900, y: -200, width: 800, height: 700)
        let origin = StudioPlacement.menuTopLeft(
            size: menuSize, beside: palette, anchorTop: 100.5, frame: frame, in: visible)
        #expect(origin == CGPoint(x: (-1000.5 - 6 - 240).rounded(), y: CGFloat(101)))
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

    // MARK: One Window's notice

    private let notice = CGSize(width: 120, height: 16)

    @Test func oneWindowNoticeGoesRightOfTheNameCentredOnItsRow() {
        let name = CGRect(x: 198, y: 408, width: 60, height: 16)
        #expect(
            StudioPlacement.oneWindowNotice(size: notice, beside: name, in: display)
                == CGRect(x: 258 + 6, y: 408, width: 120, height: 16))
    }

    @Test func oneWindowNoticeCentresOnATallerRow() {
        // The palette level with a 36 pt One Window button: centred on it, on whole points.
        let row = CGRect(x: 40, y: 500, width: 52, height: 36)
        #expect(
            StudioPlacement.oneWindowNotice(size: notice, beside: row, in: display)
                == CGRect(x: 92 + 6, y: 510, width: 120, height: 16))
        let odd = CGRect(x: 40, y: 500, width: 52, height: 35)
        #expect(StudioPlacement.oneWindowNotice(size: notice, beside: odd, in: display).minY == CGFloat(510))
    }

    @Test func oneWindowNoticeGoesLeftWithoutRoomOnTheRight() {
        // 1440 − 8 is as far right as it may reach: 1312 + 120 fits, 1313 + 120 doesn't.
        let fits = CGRect(x: 1256, y: 400, width: 50, height: 16)
        #expect(StudioPlacement.oneWindowNotice(size: notice, beside: fits, in: display).minX == CGFloat(1312))
        let over = CGRect(x: 1257, y: 400, width: 50, height: 16)
        #expect(
            StudioPlacement.oneWindowNotice(size: notice, beside: over, in: display).minX == CGFloat(1257 - 6 - 120))
    }

    @Test func oneWindowNoticeStaysOnTheDisplay() {
        // No room on either side: kept inside, over what it sits beside.
        let wide = CGRect(x: 4, y: 400, width: 1430, height: 16)
        #expect(StudioPlacement.oneWindowNotice(size: notice, beside: wide, in: display).minX == CGFloat(8))
        // At the display's top and bottom.
        let top = CGRect(x: 100, y: 890, width: 60, height: 16)
        #expect(StudioPlacement.oneWindowNotice(size: notice, beside: top, in: display).maxY == CGFloat(900 - 8))
        let bottom = CGRect(x: 100, y: -10, width: 60, height: 16)
        #expect(StudioPlacement.oneWindowNotice(size: notice, beside: bottom, in: display).minY == CGFloat(8))
    }

    @Test func oneWindowNoticeOnADisplayWithNegativeCoordinates() {
        let visible = CGRect(x: -1920, y: -1080, width: 1920, height: 1055)
        let name = CGRect(x: -1502, y: -492, width: 60, height: 16)
        #expect(
            StudioPlacement.oneWindowNotice(size: notice, beside: name, in: visible)
                == CGRect(x: -1442 + 6, y: -492, width: 120, height: 16))
        // At its right edge, x 0: left of the name.
        let atEdge = CGRect(x: -100, y: -492, width: 60, height: 16)
        #expect(
            StudioPlacement.oneWindowNotice(size: notice, beside: atEdge, in: visible).minX
                == CGFloat(-100 - 6 - 120))
    }

    @Test func oneWindowNoticeOnHalfPointsLandsOnWholePoints() {
        let name = CGRect(x: 99.5, y: 199.5, width: 60, height: 16)
        let rect = StudioPlacement.oneWindowNotice(size: notice, beside: name, in: display)
        #expect(rect.minX == rect.minX.rounded() && rect.minY == rect.minY.rounded())
    }
}
