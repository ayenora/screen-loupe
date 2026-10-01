import Testing

struct ToolbarSelectionTests {
    @Test func aSegmentTurnedOnIsTheOneClicked() {
        #expect(ToolbarSelection.clicked(shown: [false, true, false], model: [false, false, false]) == 1)
    }

    @Test func aSegmentTurnedOffIsTheOneClicked() {
        #expect(ToolbarSelection.clicked(shown: [true, false, false], model: [true, true, false]) == 1)
    }

    @Test func otherSegmentsThatAreOnDontCount() {
        // The Color Meter and References open; Recent Captures clicked.
        #expect(ToolbarSelection.clicked(shown: [true, true, true], model: [true, true, false]) == 2)
    }

    @Test func aSegmentTurnedOffBesideOthersOn() {
        // The Color Meter clicked off while the other two show on.
        #expect(ToolbarSelection.clicked(shown: [false, true, true], model: [true, true, true]) == 0)
    }

    @Test func nothingClickedWhenTheyAgree() {
        #expect(ToolbarSelection.clicked(shown: [true, false, true], model: [true, false, true]) == nil)
        #expect(ToolbarSelection.clicked(shown: [], model: []) == nil)
    }

    @Test func theFirstDifferenceWins() {
        #expect(ToolbarSelection.clicked(shown: [false, true, true], model: [false, false, false]) == 1)
    }

    @Test func onlyTheSegmentsBothHaveCount() {
        #expect(ToolbarSelection.clicked(shown: [false, false, true], model: [false, false]) == nil)
        #expect(ToolbarSelection.clicked(shown: [false], model: [false, true]) == nil)
    }
}
