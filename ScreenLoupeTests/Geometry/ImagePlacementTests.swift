import CoreGraphics
import Testing

struct ImagePlacementTests {
    @Test func referencesOpenTakesTheImageAsALayer() {
        #expect(ImagePlacement.of(chosen: nil, showsReferences: true, showsCaptures: false) == .place(.references))
    }

    @Test func recentCapturesOpenTakesTheImageToInspect() {
        #expect(ImagePlacement.of(chosen: nil, showsReferences: false, showsCaptures: true) == .place(.captures))
    }

    @Test func neitherPanelOpenAsks() {
        #expect(ImagePlacement.of(chosen: nil, showsReferences: false, showsCaptures: false) == .ask)
    }

    /// The panels share one place, so both open doesn't happen; References would come first.
    @Test func bothOpenGoesToReferences() {
        #expect(ImagePlacement.of(chosen: nil, showsReferences: true, showsCaptures: true) == .place(.references))
    }

    static let panels: [(Bool, Bool)] = [(false, false), (true, false), (false, true), (true, true)]

    @Test(arguments: panels)
    func anExplicitCommandGoesWhereItSaysWhateverIsOpen(showsReferences: Bool, showsCaptures: Bool) {
        for chosen in [ImageDestination.references, .captures] {
            #expect(
                ImagePlacement.of(chosen: chosen, showsReferences: showsReferences, showsCaptures: showsCaptures)
                    == .place(chosen))
        }
    }

    // MARK: The menu's point

    private let area = CGRect(x: 0, y: 0, width: 400, height: 300)

    @Test func aPointerOverTheImageAreaIsWhereTheMenuComesUp() {
        #expect(ImagePlacement.menuPoint(pointer: CGPoint(x: 120, y: 40), imageArea: area) == CGPoint(x: 120, y: 40))
    }

    @Test func aPointerOutsideTheImageAreaGivesItsCentre() {
        // Over the side column, right of the image area.
        #expect(ImagePlacement.menuPoint(pointer: CGPoint(x: 500, y: 40), imageArea: area) == CGPoint(x: 200, y: 150))
        #expect(ImagePlacement.menuPoint(pointer: CGPoint(x: -1, y: 40), imageArea: area) == CGPoint(x: 200, y: 150))
    }

    @Test func anUnknownPointerGivesTheCentre() {
        #expect(ImagePlacement.menuPoint(pointer: nil, imageArea: area) == CGPoint(x: 200, y: 150))
    }

    /// `CGRect.contains` takes the minimum edges and leaves out the maximum ones.
    @Test func theAreaEdges() {
        #expect(ImagePlacement.menuPoint(pointer: .zero, imageArea: area) == .zero)
        #expect(ImagePlacement.menuPoint(pointer: CGPoint(x: 400, y: 10), imageArea: area) == CGPoint(x: 200, y: 150))
    }

    @Test func anOffsetImageAreaCentresOnItself() {
        let offset = CGRect(x: 20, y: 30, width: 100, height: 50)
        #expect(ImagePlacement.menuPoint(pointer: nil, imageArea: offset) == CGPoint(x: 70, y: 55))
    }

    @Test func anEmptyImageAreaTakesNoPointer() {
        let empty = CGRect(x: 10, y: 10, width: 0, height: 0)
        #expect(ImagePlacement.menuPoint(pointer: CGPoint(x: 10, y: 10), imageArea: empty) == CGPoint(x: 10, y: 10))
    }
}
