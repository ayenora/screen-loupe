import CoreGraphics
import Testing

struct PaletteHitShapeTests {
    /// The macOS 15 look: a group 32 pt wide with 8 pt corners.
    private let rect = CGRect(x: 0, y: 0, width: 32, height: 84)
    private let radius: CGFloat = 8

    private func inside(_ x: CGFloat, _ y: CGFloat, _ r: CGRect? = nil, radius: CGFloat? = nil) -> Bool {
        PaletteHitShape.contains(CGPoint(x: x, y: y), roundedRect: r ?? rect, radius: radius ?? self.radius)
    }

    /// A point `offset` from the bottom-left arc along its 45° line: negative is inside the arc.
    private func onDiagonal(_ offset: CGFloat, radius r: CGFloat) -> CGPoint {
        let d = r / 2.squareRoot() + offset / 2.squareRoot()
        return CGPoint(x: r - d, y: r - d)
    }

    @Test func centreIsInside() {
        #expect(inside(16, 42))
    }

    @Test func squareCornersAreOutside() {
        #expect(!inside(0, 0))
        #expect(!inside(32, 0))
        #expect(!inside(0, 84))
        #expect(!inside(32, 84))
    }

    @Test func justInsideTheArcAt45DegreesIsInside() {
        let p = onDiagonal(-0.01, radius: radius)
        #expect(inside(p.x, p.y))
    }

    @Test func justOutsideTheArcAt45DegreesIsOutside() {
        let p = onDiagonal(0.01, radius: radius)
        #expect(!inside(p.x, p.y))
    }

    /// Mirrored into each corner, as the shape is symmetric.
    @Test func everyCornerArcIsRounded() {
        let outer = onDiagonal(0.01, radius: radius)
        let inner = onDiagonal(-0.01, radius: radius)
        for (sx, sy) in [(false, true), (true, false), (true, true)] {
            let ox = sx ? rect.maxX - outer.x : outer.x
            let oy = sy ? rect.maxY - outer.y : outer.y
            let ix = sx ? rect.maxX - inner.x : inner.x
            let iy = sy ? rect.maxY - inner.y : inner.y
            #expect(!inside(ox, oy))
            #expect(inside(ix, iy))
        }
    }

    @Test func pointsOnTheStraightEdgesAreInside() {
        #expect(inside(0, 42))
        #expect(inside(32, 42))
        #expect(inside(16, 0))
        #expect(inside(16, 84))
        // Where an edge meets an arc.
        #expect(inside(0, 8))
        #expect(inside(8, 0))
    }

    @Test func outsideTheRectIsOutside() {
        #expect(!inside(-0.01, 42))
        #expect(!inside(32.01, 42))
        #expect(!inside(16, -0.01))
        #expect(!inside(16, 84.01))
    }

    /// The glass look: a group 36 pt wide with a radius of half that, round at both ends.
    @Test func capsuleWithRadiusHalfTheWidth() {
        let group = CGRect(x: 0, y: 0, width: 36, height: 108)
        #expect(inside(18, 0, group, radius: 18))
        #expect(inside(0, 18, group, radius: 18))
        #expect(!inside(0, 17, group, radius: 18))
        #expect(!inside(2, 2, group, radius: 18))
        #expect(!inside(34, 106, group, radius: 18))
        #expect(inside(0, 54, group, radius: 18))
        #expect(inside(36, 90, group, radius: 18))
    }

    @Test func radiusZeroIsTheWholeRect() {
        #expect(inside(0, 0, radius: 0))
        #expect(inside(32, 84, radius: 0))
        #expect(!inside(-0.01, 0, radius: 0))
    }

    @Test func negativeRadiusIsTheWholeRect() {
        #expect(inside(0, 0, radius: -4))
    }

    /// A radius beyond half the shorter side is a capsule, as `NSBezierPath` draws it.
    @Test func radiusLargerThanHalfTheSideIsClamped() {
        let group = CGRect(x: 0, y: 0, width: 36, height: 108)
        for (x, y) in [(18.0, 0.0), (0.0, 18.0), (0.0, 54.0), (2.0, 2.0), (0.0, 17.0)] {
            #expect(inside(x, y, group, radius: 100) == inside(x, y, group, radius: 18))
        }
    }

    @Test func squareWithOversizedRadiusIsACircle() {
        let square = CGRect(x: 0, y: 0, width: 20, height: 20)
        #expect(inside(10, 0, square, radius: 50))
        #expect(inside(10, 10, square, radius: 50))
        #expect(!inside(2, 2, square, radius: 50))
    }

    @Test func emptyRectHasNothingInside() {
        #expect(!inside(0, 0, CGRect(x: 0, y: 0, width: 0, height: 20)))
        #expect(!inside(0, 0, CGRect(x: 0, y: 0, width: 20, height: 0)))
    }

    @Test func offsetRectIsMeasuredFromItsOwnOrigin() {
        let group = CGRect(x: 100, y: -50, width: 32, height: 84)
        #expect(inside(116, -8, group))
        #expect(!inside(100, -50, group))
        #expect(inside(100, -42, group))
        #expect(!inside(0, 0, group))
    }

    @Test func nonIntegerSizes() {
        let group = CGRect(x: 0.5, y: 0.25, width: 31.5, height: 27.75)
        #expect(inside(16.25, 14.125, group, radius: 7.5))
        #expect(!inside(0.5, 0.25, group, radius: 7.5))
        #expect(inside(0.5, 7.75, group, radius: 7.5))
        let d = 7.5 - 7.5 / 2.squareRoot()
        #expect(inside(0.5 + d + 0.01, 0.25 + d + 0.01, group, radius: 7.5))
        #expect(!inside(0.5 + d - 0.01, 0.25 + d - 0.01, group, radius: 7.5))
    }

    // MARK: Buttons in a group

    /// Three 32 × 28 pt buttons one under another in a group with 8 pt corners, first at the top
    /// (the group's coordinates here are bottom-up; the shape is symmetric either way).
    private let group = CGRect(x: 0, y: 0, width: 32, height: 84)
    private let first = CGRect(x: 0, y: 56, width: 32, height: 28)
    private let middle = CGRect(x: 0, y: 28, width: 32, height: 28)
    private let last = CGRect(x: 0, y: 0, width: 32, height: 28)

    private func takes(_ button: CGRect, _ x: CGFloat, _ y: CGFloat) -> Bool {
        PaletteHitShape.buttonTakes(CGPoint(x: x, y: y), buttonFrame: button, group: group, radius: radius)
    }

    @Test func eachButtonTakesItsMiddle() {
        #expect(takes(first, 16, 70))
        #expect(takes(middle, 16, 42))
        #expect(takes(last, 16, 14))
    }

    @Test func firstButtonLeavesItsOuterCornersOnly() {
        #expect(!takes(first, 0.5, 83.5))
        #expect(!takes(first, 31.5, 83.5))
        #expect(takes(first, 0.5, 56.5))
        #expect(takes(first, 31.5, 56.5))
    }

    @Test func middleButtonTakesItsWholeSquare() {
        #expect(takes(middle, 0, 28))
        #expect(takes(middle, 0.1, 55.9))
        #expect(takes(middle, 31.9, 28))
        #expect(takes(middle, 31.9, 55.9))
    }

    @Test func lastButtonLeavesItsOuterCornersOnly() {
        #expect(!takes(last, 0.5, 0.5))
        #expect(!takes(last, 31.5, 0.5))
        #expect(takes(last, 0.5, 27.5))
        #expect(takes(last, 31.5, 27.5))
    }

    /// Where two buttons touch, only the one whose half-open frame holds the point takes it.
    @Test func touchingButtonsShareNoPoint() {
        #expect(takes(middle, 16, 56) == false)
        #expect(takes(first, 16, 56))
        #expect(takes(last, 16, 28) == false)
        #expect(takes(middle, 16, 28))
    }

    @Test func pointOutsideTheButtonIsNotTakenThoughInTheGroup() {
        #expect(!takes(first, 16, 42))
        #expect(!takes(last, 16, 70))
    }

    /// A glass group: its first and last buttons are half-discs at the outer end.
    @Test func glassGroupEndsAreHalfDiscs() {
        let glass = CGRect(x: 0, y: 0, width: 36, height: 108)
        let top = CGRect(x: 0, y: 72, width: 36, height: 36)
        let bottom = CGRect(x: 0, y: 0, width: 36, height: 36)
        let take = { (b: CGRect, x: CGFloat, y: CGFloat) in
            PaletteHitShape.buttonTakes(CGPoint(x: x, y: y), buttonFrame: b, group: glass, radius: 18)
        }
        #expect(take(top, 18, 90))
        #expect(!take(top, 1, 107))
        #expect(take(top, 1, 90))
        #expect(take(top, 1, 72.5))
        #expect(take(bottom, 18, 18))
        #expect(!take(bottom, 35, 1))
        #expect(take(bottom, 35, 35.5))
    }

    /// The glass group of One Window and its ▾ alone, bottom-up: One Window's 36 pt slot, then the
    /// ▾'s view, 28 pt wide as its highlight, overlapping One Window by 6 pt, so the group is 58 ×
    /// 36 pt, a capsule, and the ▾'s 16 pt hit slot is 36…52.
    private let wideGroup = CGRect(x: 0, y: 0, width: 58, height: 36)
    private let oneWindow = CGRect(x: 0, y: 0, width: 36, height: 36)
    private var menu: CGRect { PaletteMenuButton.hitSlot(in: CGRect(x: 30, y: 0, width: 28, height: 36)) }

    private func takesWide(_ button: CGRect, _ x: CGFloat, _ y: CGFloat) -> Bool {
        PaletteHitShape.buttonTakes(CGPoint(x: x, y: y), buttonFrame: button, group: wideGroup, radius: 18)
    }

    @Test func theMenusHitSlotIsItsMiddle16Points() {
        #expect(menu == CGRect(x: 36, y: 0, width: 16, height: 36))
    }

    @Test func eachButtonOfTheWiderGroupTakesItsMiddle() {
        #expect(takesWide(oneWindow, 18, 18))
        #expect(takesWide(menu, 44, 18))
    }

    @Test func oneWindowKeepsWhatTheMenusHighlightOverlaps() {
        // 30…36 is under the ▾'s view, but only One Window takes it.
        #expect(takesWide(oneWindow, 31, 18))
        #expect(!takesWide(menu, 31, 18))
        #expect(takesWide(menu, 36, 18))
        #expect(!takesWide(oneWindow, 36, 18))
    }

    @Test func pastTheMenusSlotIsTheGroupsBackground() {
        // 52…58: the ▾'s highlight reaches there, the mouse drags the palette.
        #expect(!takesWide(menu, 52, 18))
        #expect(!takesWide(menu, 55, 18))
        #expect(takesWide(menu, 51.9, 18))
    }

    @Test func oneWindowsLeftEndIsTheCapsulesRoundEnd() {
        // The left arc's centre is (18, 18): 17.5 pt to its left is inside, the corners outside.
        #expect(takesWide(oneWindow, 0.5, 18))
        #expect(!takesWide(oneWindow, 1, 1))
        #expect(!takesWide(oneWindow, 1, 33))
        // Between the arcs, its top and bottom edges are straight.
        #expect(takesWide(oneWindow, 26, 35.9))
        #expect(takesWide(oneWindow, 26, 0))
        #expect(!takesWide(oneWindow, 26, 36))
    }

    @Test func theMenusHighlightFitsTheGroupsRoundedEnd() {
        // A 28 pt circle centred on the ▾'s slot, (44, 18), stays inside the 58 × 36 pt capsule:
        // its rightmost, lowest and highest points are inside.
        let r = PaletteHitShape.contains
        #expect(r(CGPoint(x: 58, y: 18), wideGroup, 18))
        #expect(r(CGPoint(x: 44, y: 4), wideGroup, 18))
        #expect(r(CGPoint(x: 44, y: 32), wideGroup, 18))
        // 45° down-right and up-right on the circle, 17.1 pt from the arc's centre at (40, 18).
        #expect(r(CGPoint(x: 44 + 14 / 2.squareRoot(), y: 18 - 14 / 2.squareRoot()), wideGroup, 18))
        #expect(r(CGPoint(x: 44 + 14 / 2.squareRoot(), y: 18 + 14 / 2.squareRoot()), wideGroup, 18))
    }
}

struct PaletteMenuButtonTests {
    @Test func theHighlightIsAsTallAsTheButtonsFillAndAtLeastTheSlotAnd5() {
        // Measured: 20 pt tall, 21 wide; 24 tall, 24 wide.
        #expect(PaletteMenuButton.fillWidth(fillHeight: 20) == CGFloat(21))
        #expect(PaletteMenuButton.fillWidth(fillHeight: 24) == CGFloat(24))
        // The palette from macOS 26: a 28 pt fill, a 28 pt circle.
        #expect(PaletteMenuButton.fillWidth(fillHeight: 28) == CGFloat(28))
        #expect(PaletteMenuButton.fillWidth(fillHeight: 0) == CGFloat(21))
    }

    @Test func theHighlightReachesEquallyPastBothSidesOfTheSlot() {
        #expect(PaletteMenuButton.overhang(fillHeight: 28) == CGFloat(6))
        #expect(PaletteMenuButton.overhang(fillHeight: 24) == CGFloat(4))
        #expect(PaletteMenuButton.overhang(fillHeight: 20) == CGFloat(2.5))
    }

    @Test func theMeasuredHighlightMeetsTheButtonsFill() {
        // A 36.5 pt button, its fill inset 2 pt: it ends at 34.5; the ▾'s 24 pt highlight around
        // 36.5…52.5 starts at 32.5, 2 pt over it, as measured.
        let slot = CGRect(x: 36.5, y: 0, width: 16, height: 28)
        let start = slot.midX - PaletteMenuButton.fillWidth(fillHeight: 24) / 2
        #expect(start == CGFloat(32.5))
    }

    @Test func theHitSlotIsTheMiddleOfTheView() {
        #expect(
            PaletteMenuButton.hitSlot(in: CGRect(x: 30, y: 0, width: 28, height: 36))
                == CGRect(x: 36, y: 0, width: 16, height: 36))
        #expect(
            PaletteMenuButton.hitSlot(in: CGRect(x: 28, y: -4, width: 24, height: 28))
                == CGRect(x: 32, y: -4, width: 16, height: 28))
        // A view no wider than the slot is all slot.
        #expect(PaletteMenuButton.hitSlot(in: CGRect(x: 0, y: 0, width: 16, height: 36)).width == CGFloat(16))
        #expect(PaletteMenuButton.hitSlot(in: CGRect(x: 0, y: 0, width: 10, height: 36)).width == CGFloat(10))
    }

    @Test func theRowIsTheButtonTheSlotAndTheOverhang() {
        #expect(PaletteMenuButton.rowWidth(buttonWidth: 36, fillHeight: 28) == CGFloat(58))
        #expect(PaletteMenuButton.rowWidth(buttonWidth: 32, fillHeight: 24) == CGFloat(52))
    }
}
