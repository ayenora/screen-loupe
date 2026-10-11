import CoreGraphics
import Testing

struct SplitKindTests {
    @Test func aReferenceSplitNamesTheLayerAndTheLiveImage() {
        #expect(SplitKind.reference.labels == ("Reference", "Live"))
    }

    @Test func theVisionSplitNamesNormalVisionAndTheMode() {
        #expect(SplitKind.vision("Deuteranopia").labels == ("Normal", "Deuteranopia"))
    }

    @Test func noSplitShowsWithNeitherOn() {
        #expect(SplitKind.shown(visionSplit: nil, referenceSplit: false) == nil)
    }

    @Test func eachSplitShowsAlone() {
        #expect(SplitKind.shown(visionSplit: "Tritanopia", referenceSplit: false) == .vision("Tritanopia"))
        #expect(SplitKind.shown(visionSplit: nil, referenceSplit: true) == .reference)
    }

    @Test func theVisionSplitShowsOverAReferenceSplit() {
        #expect(SplitKind.shown(visionSplit: "Grayscale", referenceSplit: true) == .vision("Grayscale"))
    }
}

struct SplitLineTests {
    // MARK: Place

    @Test func itStartsInTheMiddle() {
        #expect(SplitLine.defaultPosition == 0.5)
        #expect(SplitLine.x(position: SplitLine.defaultPosition, width: 800) == 400)
    }

    @Test(arguments: [(-0.2, 0.0), (0, 0), (0.25, 0.25), (1, 1), (1.7, 1)])
    func aPlaceStaysWithinTheEdges(position: Double, kept: Double) {
        #expect(SplitLine.clamped(position) == kept)
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity])
    func aPlaceThatIsNoNumberIsTheMiddle(position: Double) {
        #expect(SplitLine.clamped(position) == SplitLine.defaultPosition)
    }

    @Test func theLineKeepsItsFractionAsTheViewerResizes() {
        #expect(SplitLine.x(position: 0.25, width: 800) == 200)
        #expect(SplitLine.x(position: 0.25, width: 1200) == 300)
        #expect(SplitLine.x(position: 0.25, width: 0) == 0)
    }

    @Test func anOutOfRangePlaceIsDrawnAtTheEdge() {
        #expect(SplitLine.x(position: 3, width: 800) == 800)
        #expect(SplitLine.x(position: -1, width: 800) == 0)
    }

    // MARK: Drag

    @Test func theLineMovesAsFarAsThePointer() {
        // Grabbed 3 px right of the line at 400, then moved 100 px right.
        #expect(SplitLine.dragged(from: 0.5, startX: 403, to: 503, width: 800) == 0.625)
        #expect(SplitLine.dragged(from: 0.5, startX: 403, to: 303, width: 800) == 0.375)
    }

    @Test func aPressWithoutMovingKeepsThePlace() {
        #expect(SplitLine.dragged(from: 0.3, startX: 241, to: 241, width: 800) == 0.3)
    }

    @Test func aDragStopsAtTheEdges() {
        #expect(SplitLine.dragged(from: 0.5, startX: 400, to: 2000, width: 800) == 1)
        #expect(SplitLine.dragged(from: 0.5, startX: 400, to: -900, width: 800) == 0)
    }

    @Test func withoutAWidthTheLineStays() {
        #expect(SplitLine.dragged(from: 0.4, startX: 0, to: 50, width: 0) == 0.4)
        #expect(SplitLine.dragged(from: 4, startX: 0, to: 50, width: 0) == 1)
    }

    // MARK: Hit testing

    /// An 800 × 600 px viewport at 2 px per point, the line at 400.
    private func hits(_ x: CGFloat, _ y: CGFloat) -> Bool {
        SplitLine.hits(CGPoint(x: x, y: y), lineX: 400, height: 600, scale: 2)
    }

    @Test func theLineTakesAPressWithinItsReachOverTheWholeHeight() {
        // 5 pt each side: 10 px at 2×.
        for y: CGFloat in [0, 1, 150, 599, 600] {
            #expect(hits(400, y))
            #expect(hits(390, y))
            #expect(hits(410, y))
        }
    }

    @Test func justBeyondTheReachPansAway() {
        #expect(!hits(389, 100))
        #expect(!hits(411, 100))
    }

    @Test func theKnobTakesAPressAllOverIt() {
        // Radius 13 pt: 26 px at 2×, centred at (400, 300).
        #expect(hits(400 + 26, 300))
        #expect(hits(400 - 26, 300))
        #expect(hits(400 + 18, 300 + 18))
        #expect(!hits(400 + 27, 300))
        #expect(!hits(400 + 19, 300 + 19))
    }

    @Test func outsideTheViewportNothingIsTaken() {
        #expect(!hits(400, -1))
        #expect(!hits(400, 601))
    }

    @Test func theReachScalesWithThePoint() {
        #expect(SplitLine.hits(CGPoint(x: 405, y: 10), lineX: 400, height: 600, scale: 1))
        #expect(!SplitLine.hits(CGPoint(x: 406, y: 10), lineX: 400, height: 600, scale: 1))
    }

    @Test func aLineAtTheEdgeIsStillTakenInside() {
        #expect(SplitLine.hits(CGPoint(x: 4, y: 10), lineX: 0, height: 600, scale: 1))
        #expect(SplitLine.hits(CGPoint(x: 796, y: 10), lineX: 800, height: 600, scale: 1))
    }

    @Test func theKnobSitsAtMidHeight() {
        #expect(SplitLine.knobCenter(lineX: 120, height: 500) == CGPoint(x: 120, y: 250))
    }

    // MARK: Labels

    @Test func aLabelPadsItsTextOnWholePoints() {
        #expect(SplitLine.labelSize(textSize: CGSize(width: 50.2, height: 13.4)) == CGSize(width: 63, height: 18))
    }

    @Test func labelsStandBesideTheLineAtTheTop() {
        let rects = SplitLine.labelRects(
            left: CGSize(width: 70, height: 18), right: CGSize(width: 40, height: 18), lineX: 400, width: 800, top: 8)
        #expect(rects.left == CGRect(x: 322, y: 8, width: 70, height: 18))
        #expect(rects.right == CGRect(x: 408, y: 8, width: 40, height: 18))
    }

    @Test func labelsSitOnWholePoints() {
        let rects = SplitLine.labelRects(
            left: CGSize(width: 70, height: 18), right: CGSize(width: 40, height: 18), lineX: 400.4, width: 800,
            top: 8)
        #expect(rects.left?.minX == 322)
        #expect(rects.right?.minX == 408)
    }

    @Test func aLabelThatWouldCrossTheLeftEdgeIsLeftOut() {
        let size = CGSize(width: 70, height: 18)
        // 8 + 70 + 4 = 82: the left label fits from a line at 82 on.
        #expect(SplitLine.labelRects(left: size, right: size, lineX: 82, width: 800, top: 8).left != nil)
        let near = SplitLine.labelRects(left: size, right: size, lineX: 81, width: 800, top: 8)
        #expect(near.left == nil)
        #expect(near.right != nil)
    }

    @Test func aLabelThatWouldCrossTheRightEdgeIsLeftOut() {
        let size = CGSize(width: 40, height: 18)
        // 800 - 4 - 40 - 8 = 748: the right label fits up to a line at 748.
        #expect(SplitLine.labelRects(left: size, right: size, lineX: 748, width: 800, top: 8).right != nil)
        let near = SplitLine.labelRects(left: size, right: size, lineX: 749, width: 800, top: 8)
        #expect(near.right == nil)
        #expect(near.left != nil)
    }

    @Test func atTheEdgeOnlyTheLabelInsideShows() {
        let size = CGSize(width: 40, height: 18)
        let atLeft = SplitLine.labelRects(left: size, right: size, lineX: 0, width: 800, top: 8)
        #expect(atLeft.left == nil)
        #expect(atLeft.right == CGRect(x: 8, y: 8, width: 40, height: 18))
        let atRight = SplitLine.labelRects(left: size, right: size, lineX: 800, width: 800, top: 8)
        #expect(atRight.right == nil)
        #expect(atRight.left == CGRect(x: 752, y: 8, width: 40, height: 18))
    }

    @Test func aViewerTooNarrowShowsNoLabel() {
        let size = CGSize(width: 70, height: 18)
        let rects = SplitLine.labelRects(left: size, right: size, lineX: 50, width: 100, top: 8)
        #expect(rects.left == nil)
        #expect(rects.right == nil)
    }

    @Test func labelsGoUnderThePills() {
        #expect(SplitLine.labelsTop(below: nil) == SplitLine.labelTop)
        #expect(SplitLine.labelsTop(below: 36) == 36 + ViewerIndicators.spacing)
        #expect(SplitLine.labelsTop(below: 35.6) == CGFloat(42))
    }

    // MARK: Copy View

    @Test func aCopyOfTheWholeViewHoldsTheLine() {
        for x: CGFloat in [0, 1, 400, 800] {
            #expect(SplitLine.isInCopy(x: x, width: 800))
        }
    }

    @Test func aSelectionBesideTheLineHoldsNeitherLineNorLabels() {
        // The line at 400 in the view; a selection copied from x 500 puts it at -100.
        #expect(!SplitLine.isInCopy(x: -100, width: 200))
        #expect(!SplitLine.isInCopy(x: 250, width: 200))
    }

    @Test func aSelectionAcrossTheLineHoldsIt() {
        #expect(SplitLine.isInCopy(x: 80, width: 200))
    }
}
