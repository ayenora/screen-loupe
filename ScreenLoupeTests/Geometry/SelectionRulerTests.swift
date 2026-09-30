import CoreGraphics
import Testing

struct RulerLabelTests {
    @Test func givesPixelsAndPointsOnARetinaDisplay() {
        #expect(RulerLabel.text(pixels: 32, sourceScale: 2) == "32 px · 16 pt")
    }

    @Test func givesAHalfPointToOneDecimal() {
        #expect(RulerLabel.text(pixels: 33, sourceScale: 2) == "33 px · 16.5 pt")
        #expect(RulerLabel.text(pixels: 10, sourceScale: 3) == "10 px · 3.3 pt")
        #expect(RulerLabel.text(pixels: 3, sourceScale: 1.5) == "3 px · 2 pt")
    }

    @Test func givesOnlyPixelsWhenAPixelIsAPoint() {
        // A 1× display, and an image file, which has no points.
        #expect(RulerLabel.text(pixels: 32, sourceScale: 1) == "32 px")
        #expect(RulerLabel.text(pixels: 1, sourceScale: 1) == "1 px")
    }
}

struct RulerChoiceTests {
    private let cornerOff = RulerChoice(mode: .corner, isOn: false)
    private let cornerOn = RulerChoice(mode: .corner, isOn: true)
    private let selectionOff = RulerChoice(mode: .selection, isOn: false)
    private let selectionOn = RulerChoice(mode: .selection, isOn: true)

    @Test func theButtonTurnsTheChosenModesRulerOnAndOff() {
        #expect(cornerOff.toggled() == cornerOn)
        #expect(cornerOn.toggled() == cornerOff)
        #expect(selectionOff.toggled() == selectionOn)
        #expect(selectionOn.toggled() == selectionOff)
    }

    @Test func aMenuItemTurnsItsRulerOnInPlaceOfTheOther() {
        #expect(cornerOn.toggled(.selection) == selectionOn)
        #expect(selectionOn.toggled(.corner) == cornerOn)
        #expect(cornerOff.toggled(.selection) == selectionOn)
        #expect(selectionOff.toggled(.corner) == cornerOn)
    }

    @Test func aMenuItemTurnsItsRulerOffWhenItIsOn() {
        #expect(cornerOn.toggled(.corner) == cornerOff)
        #expect(selectionOn.toggled(.selection) == selectionOff)
    }

    @Test func choosingAModeInTheButtonsMenuAlwaysLeavesItOn() {
        #expect(cornerOff.turnedOn(.corner) == cornerOn)
        #expect(cornerOn.turnedOn(.corner) == cornerOn)
        #expect(cornerOn.turnedOn(.selection) == selectionOn)
        #expect(selectionOff.turnedOn(.corner) == cornerOn)
        #expect(selectionOn.turnedOn(.selection) == selectionOn)
    }

    @Test func theButtonThenUsesTheModeChosenLast() {
        #expect(cornerOn.turnedOn(.selection).toggled() == selectionOff)
        #expect(selectionOn.toggled(.corner).toggled() == cornerOff)
    }
}

/// A 400 × 300 pt image area, and 80 × 18 pt labels.
struct SelectionRulerTests {
    private let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
    private let label = CGSize(width: 80, height: 18)

    // MARK: Width

    @Test func theWidthIsALineAboveTheTopEdgeWithItsLabelCentredOnIt() {
        let line = SelectionRuler.widthLine(
            of: CGRect(x: 100, y: 100, width: 120, height: 60), in: bounds, labelSize: label)
        #expect(line.side == .outside)
        #expect(line.start == CGPoint(x: 100, y: 88))
        #expect(line.end == CGPoint(x: 220, y: 88))
        #expect(line.label == CGRect(x: 120, y: 79, width: 80, height: 18))
        // Clear of the selection's pixels.
        #expect(line.label.maxY < 100)
    }

    @Test func theWidthGoesBelowWithNoRoomAbove() {
        let line = SelectionRuler.widthLine(
            of: CGRect(x: 100, y: 5, width: 120, height: 60), in: bounds, labelSize: label)
        #expect(line.side == .opposite)
        #expect(line.start == CGPoint(x: 100, y: 77))
        #expect(line.end == CGPoint(x: 220, y: 77))
        #expect(line.label.minY == 68)
        #expect(line.label.minY > 65)
    }

    @Test func theWidthStaysAboveWhileItsLabelJustFits() {
        // 12 pt off the edge and half the label's 18: 21 pt of room.
        let fits = SelectionRuler.widthLine(
            of: CGRect(x: 100, y: 21, width: 120, height: 60), in: bounds, labelSize: label)
        #expect(fits.side == .outside)
        #expect(fits.label.minY == 0)
        let tight = SelectionRuler.widthLine(
            of: CGRect(x: 100, y: 20, width: 120, height: 60), in: bounds, labelSize: label)
        #expect(tight.side == .opposite)
    }

    @Test func theWidthGoesInsideWithNoRoomAboveOrBelow() {
        let line = SelectionRuler.widthLine(
            of: CGRect(x: 100, y: 5, width: 120, height: 290), in: bounds, labelSize: label)
        #expect(line.side == .inside)
        #expect(line.start == CGPoint(x: 100, y: 17))
        #expect(line.end == CGPoint(x: 220, y: 17))
    }

    @Test func insideASelectionTallerThanTheViewTheWidthRunsAlongTheVisibleTop() {
        let line = SelectionRuler.widthLine(
            of: CGRect(x: 100, y: -50, width: 120, height: 400), in: bounds, labelSize: label)
        #expect(line.side == .inside)
        #expect(line.start.y == 12)
    }

    @Test func theWidthsLabelCentresOnThePartOfTheLineInView() {
        let line = SelectionRuler.widthLine(
            of: CGRect(x: -200, y: 100, width: 400, height: 60), in: bounds, labelSize: label)
        // The line runs from -200 to 200; 0 to 200 shows.
        #expect(line.start.x == -200)
        #expect(line.label.minX == 60)
    }

    @Test func theWidthsLabelStaysInsideTheView() {
        let line = SelectionRuler.widthLine(
            of: CGRect(x: 380, y: 100, width: 100, height: 60), in: bounds, labelSize: label)
        #expect(line.label.maxX == 400)
        let left = SelectionRuler.widthLine(
            of: CGRect(x: 0, y: 100, width: 10, height: 60), in: bounds, labelSize: label)
        #expect(left.label.minX == 0)
    }

    @Test func aLineOutOfViewKeepsItsLabelWithIt() {
        let line = SelectionRuler.widthLine(
            of: CGRect(x: 500, y: 100, width: 100, height: 60), in: bounds, labelSize: label)
        #expect(line.label.minX == 510)
    }

    @Test func aSelectionNarrowerThanItsLabelCentresTheLabelOverIt() {
        let line = SelectionRuler.widthLine(
            of: CGRect(x: 100, y: 100, width: 2, height: 2), in: bounds, labelSize: label)
        #expect(line.label.midX == 101)
    }

    @Test func labelsSitOnWholePoints() {
        // Zoomed so the selection's edges fall between points.
        let rect = CGRect(x: 100.25, y: 100.5, width: 121, height: 60.5)
        let width = SelectionRuler.widthLine(of: rect, in: bounds, labelSize: label)
        #expect(width.label.minX == width.label.minX.rounded())
        #expect(width.label.minY == width.label.minY.rounded())
        let height = SelectionRuler.heightLine(of: rect, in: bounds, labelSize: label)
        #expect(height.label.minX == height.label.minX.rounded())
        #expect(height.label.minY == height.label.minY.rounded())
        // The lines stay on the selection's edges.
        #expect(width.start.x == 100.25)
        #expect(width.end.x == 221.25)
        #expect(height.start.y == 100.5)
        #expect(height.end.y == 161)
    }

    // MARK: Height

    @Test func theHeightIsALineLeftOfTheLeftEdgeWithItsLabelBesideIt() {
        let line = SelectionRuler.heightLine(
            of: CGRect(x: 100, y: 100, width: 120, height: 60), in: bounds, labelSize: label)
        #expect(line.side == .outside)
        #expect(line.start == CGPoint(x: 88, y: 100))
        #expect(line.end == CGPoint(x: 88, y: 160))
        #expect(line.label == CGRect(x: 2, y: 121, width: 80, height: 18))
        #expect(line.label.maxX < 88)
    }

    @Test func theHeightGoesRightWithNoRoomLeft() {
        let line = SelectionRuler.heightLine(
            of: CGRect(x: 50, y: 100, width: 120, height: 60), in: bounds, labelSize: label)
        #expect(line.side == .opposite)
        #expect(line.start == CGPoint(x: 182, y: 100))
        #expect(line.end == CGPoint(x: 182, y: 160))
        #expect(line.label.minX == 188)
    }

    @Test func theHeightStaysLeftWhileItsLabelJustFits() {
        // 12 pt off the edge, 6 to the label and its 80: 98 pt of room.
        let fits = SelectionRuler.heightLine(
            of: CGRect(x: 98, y: 100, width: 120, height: 60), in: bounds, labelSize: label)
        #expect(fits.side == .outside)
        #expect(fits.label.minX == 0)
        let tight = SelectionRuler.heightLine(
            of: CGRect(x: 97, y: 100, width: 120, height: 60), in: bounds, labelSize: label)
        #expect(tight.side == .opposite)
    }

    @Test func theHeightGoesInsideWithNoRoomLeftOrRight() {
        let line = SelectionRuler.heightLine(
            of: CGRect(x: 50, y: 100, width: 300, height: 60), in: bounds, labelSize: label)
        #expect(line.side == .inside)
        #expect(line.start == CGPoint(x: 62, y: 100))
        #expect(line.label.minX == 68)
    }

    @Test func insideASelectionWiderThanTheViewTheHeightRunsAlongTheVisibleLeft() {
        let line = SelectionRuler.heightLine(
            of: CGRect(x: -100, y: 100, width: 600, height: 60), in: bounds, labelSize: label)
        #expect(line.side == .inside)
        #expect(line.start.x == 12)
    }

    @Test func theHeightsLabelCentresOnThePartOfTheLineInViewAndStaysInside() {
        let tall = SelectionRuler.heightLine(
            of: CGRect(x: 200, y: -100, width: 50, height: 300), in: bounds, labelSize: label)
        // 0 to 200 shows.
        #expect(tall.label.minY == 91)
        let low = SelectionRuler.heightLine(
            of: CGRect(x: 200, y: 290, width: 50, height: 60), in: bounds, labelSize: label)
        #expect(low.label.maxY == 300)
    }
}

/// Over a selection smaller than the labels, the two labels meet at the corner the lines share.
/// A 400 × 300 pt image area, and 80 × 18 pt labels.
struct SelectionRulerLabelsTests {
    private let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
    private let label = CGSize(width: 80, height: 18)

    @Test func overATinySelectionTheHeightsLabelMovesDownClearOfTheWidths() {
        // 8 × 8 pt: the width's label, centred above, reaches left past the height line, and the
        // height's, centred beside its 8 pt line, reaches up into it.
        let rect = CGRect(x: 100, y: 100, width: 8, height: 8)
        let alone = SelectionRuler.heightLine(of: rect, in: bounds, labelSize: label)
        let lines = SelectionRuler.lines(of: rect, in: bounds, widthLabel: label, heightLabel: label)
        #expect(alone.label.intersects(lines.width.label))
        #expect(lines.width.side == .outside)
        #expect(lines.height.side == .outside)
        #expect(!lines.height.label.intersects(lines.width.label))
        #expect(lines.height.label == CGRect(x: alone.label.minX, y: 103, width: 80, height: 18))
        // Still beside its line, away from the selection.
        #expect(lines.height.label.maxX < lines.height.start.x)
    }

    @Test func withTheWidthBelowTheHeightsLabelMovesUpClearOfIt() {
        // Near the top: no room above, so the width line is below and its label reaches up into
        // the height's.
        let rect = CGRect(x: 100, y: 18, width: 8, height: 8)
        let lines = SelectionRuler.lines(of: rect, in: bounds, widthLabel: label, heightLabel: label)
        #expect(lines.width.side == .opposite)
        #expect(lines.width.label.minY == 29)
        #expect(lines.height.label.minY == 5)
        #expect(!lines.height.label.intersects(lines.width.label))
    }

    @Test func withNoRoomUpTheHeightsLabelGoesDownPastTheWidths() {
        let rect = CGRect(x: 100, y: 10, width: 8, height: 8)
        let lines = SelectionRuler.lines(of: rect, in: bounds, widthLabel: label, heightLabel: label)
        #expect(lines.width.side == .opposite)
        #expect(lines.height.label.minY == lines.width.label.maxY + SelectionRuler.labelGap)
        #expect(!lines.height.label.intersects(lines.width.label))
        #expect(bounds.contains(lines.height.label))
    }

    @Test func labelsThatDoNotMeetStayWhereEachLinePutsThem() {
        let rect = CGRect(x: 100, y: 100, width: 120, height: 60)
        let lines = SelectionRuler.lines(of: rect, in: bounds, widthLabel: label, heightLabel: label)
        #expect(lines.width == SelectionRuler.widthLine(of: rect, in: bounds, labelSize: label))
        #expect(lines.height == SelectionRuler.heightLine(of: rect, in: bounds, labelSize: label))
    }
}

/// The selection's size badge and the Selection Ruler share one rule, so they never overlap. A
/// 400 × 300 pt image area, 150 × 20 pt badges and 80 × 18 pt labels.
struct SelectionBadgeTests {
    private let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
    private let badge = CGSize(width: 150, height: 20)
    private let label = CGSize(width: 80, height: 18)

    private func ruler(_ rect: CGRect) -> (width: SelectionRuler.Line, height: SelectionRuler.Line) {
        SelectionRuler.lines(of: rect, in: bounds, widthLabel: label, heightLabel: label)
    }

    /// Clear of both lines, their end marks and their labels.
    private func isClear(_ placed: CGRect, of ruler: (width: SelectionRuler.Line, height: SelectionRuler.Line)) -> Bool
    {
        [ruler.width, ruler.height].allSatisfy { line in
            let area = CGRect(
                x: min(line.start.x, line.end.x), y: min(line.start.y, line.end.y),
                width: abs(line.end.x - line.start.x), height: abs(line.end.y - line.start.y)
            ).insetBy(dx: -SelectionRuler.markReach, dy: -SelectionRuler.markReach)
            return !area.intersects(placed) && !line.label.intersects(placed)
        }
    }

    @Test func withoutTheRulerTheBadgeGoesUnderTheBottomLeftCorner() {
        let rect = CGRect(x: 100, y: 100, width: 120, height: 60)
        #expect(
            SelectionRuler.badgeRect(size: badge, for: rect, in: bounds, ruler: nil)
                == CGRect(x: 100, y: 166, width: 150, height: 20))
    }

    @Test func withoutTheRulerOrRoomBelowTheBadgeGoesOverTheTop() {
        let rect = CGRect(x: 100, y: 200, width: 120, height: 90)
        #expect(SelectionRuler.badgeRect(size: badge, for: rect, in: bounds, ruler: nil).minY == 174)
    }

    @Test func withRoomAboveTheWidthLineIsThereAndTheBadgeStaysUnder() {
        let rect = CGRect(x: 100, y: 100, width: 120, height: 60)
        let lines = ruler(rect)
        #expect(lines.width.side == .outside)
        let placed = SelectionRuler.badgeRect(size: badge, for: rect, in: bounds, ruler: lines)
        #expect(placed == CGRect(x: 100, y: 166, width: 150, height: 20))
        #expect(isClear(placed, of: lines))
    }

    @Test func withNoRoomAboveTheBadgeGoesBelowTheWidthLineAndItsLabel() {
        let rect = CGRect(x: 100, y: 5, width: 120, height: 60)
        let lines = ruler(rect)
        #expect(lines.width.side == .opposite)
        let placed = SelectionRuler.badgeRect(size: badge, for: rect, in: bounds, ruler: lines)
        #expect(placed == CGRect(x: 100, y: 87, width: 150, height: 20))
        #expect(placed.minY > lines.width.label.maxY)
        #expect(isClear(placed, of: lines))
    }

    @Test func withNoRoomBelowEitherTheBadgeGoesInsideAtTheBottom() {
        let rect = CGRect(x: 100, y: 5, width: 120, height: 280)
        let lines = ruler(rect)
        #expect(lines.width.side == .inside)
        let placed = SelectionRuler.badgeRect(size: badge, for: rect, in: bounds, ruler: lines)
        #expect(placed == CGRect(x: 106, y: 259, width: 150, height: 20))
        #expect(isClear(placed, of: lines))
        #expect(bounds.contains(placed))
    }

    @Test func overASelectionFillingTheViewerTheBadgeIsInsideRightOfTheHeightLine() {
        let rect = CGRect(x: -50, y: -50, width: 500, height: 400)
        let lines = ruler(rect)
        #expect(lines.width.side == .inside)
        #expect(lines.height.side == .inside)
        let placed = SelectionRuler.badgeRect(size: badge, for: rect, in: bounds, ruler: lines)
        #expect(placed == CGRect(x: 22, y: 274, width: 150, height: 20))
        #expect(isClear(placed, of: lines))
        #expect(bounds.contains(placed))
    }

    @Test func aShortSelectionsBadgeGoesBelowAHeightLabelHangingUnderIt() {
        // 4 pt tall at the left side: the height line goes right, its label, clear of the width's,
        // reaching below.
        let rect = CGRect(x: 50, y: 100, width: 20, height: 4)
        let lines = ruler(rect)
        #expect(lines.height.side == .opposite)
        #expect(lines.height.label.minY == 103)
        let placed = SelectionRuler.badgeRect(size: badge, for: rect, in: bounds, ruler: lines)
        #expect(placed == CGRect(x: 50, y: 127, width: 150, height: 20))
        #expect(isClear(placed, of: lines))
    }

    @Test func theBadgeStaysInsideTheViewersSides() {
        let right = SelectionRuler.badgeRect(
            size: badge, for: CGRect(x: 380, y: 100, width: 10, height: 10), in: bounds, ruler: nil)
        #expect(right.maxX == 396)
        let left = SelectionRuler.badgeRect(
            size: badge, for: CGRect(x: -40, y: 100, width: 100, height: 10), in: bounds, ruler: nil)
        #expect(left.minX == 4)
    }

    @Test func theBadgeSitsOnWholePoints() {
        let rect = CGRect(x: 100.25, y: 100.5, width: 120, height: 60.25)
        let placed = SelectionRuler.badgeRect(size: badge, for: rect, in: bounds, ruler: ruler(rect))
        #expect(placed.minX == placed.minX.rounded())
        #expect(placed.minY == placed.minY.rounded())
    }
}
