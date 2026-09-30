import Testing

struct ColorContrastTests {
    private func contrast(_ text: String, on background: String) -> ColorContrast {
        ColorContrast(text: ColorSample(srgbHex: text), background: ColorSample(srgbHex: background))
    }

    @Test func blackOnWhiteIsTwentyOneAndPassesEverything() {
        let check = contrast("#000000", on: "#FFFFFF")
        #expect(check.hundredths == 2100)
        #expect(check.ratioText == "21.00:1")
        #expect(ColorContrast.Level.allCases.allSatisfy(check.passes))
    }

    @Test func theRatioIsTheSameEitherWayRound() {
        #expect(contrast("#FFFFFF", on: "#000000") == contrast("#000000", on: "#FFFFFF"))
        #expect(contrast("#0A6FE0", on: "#F2F2F2") == contrast("#F2F2F2", on: "#0A6FE0"))
    }

    @Test func identicalColoursAreOneAndFailEverything() {
        let check = contrast("#808080", on: "#808080")
        #expect(check.hundredths == 100)
        #expect(check.ratioText == "1.00:1")
        #expect(!ColorContrast.Level.allCases.contains(where: check.passes))
    }

    @Test func grey777OnWhiteFailsTextAAButPassesLargeAA() {
        let check = contrast("#777777", on: "#FFFFFF")
        #expect(check.ratioText == "4.47:1")
        #expect(!check.passes(.textAA))
        #expect(check.passes(.largeAA))
        #expect(!check.passes(.textAAA))
        #expect(!check.passes(.largeAAA))
    }

    @Test func grey767676OnWhitePassesAAAndLargeAAA() {
        let check = contrast("#767676", on: "#FFFFFF")
        #expect(check.ratioText == "4.54:1")
        #expect(check.passes(.textAA))
        #expect(check.passes(.largeAA))
        #expect(!check.passes(.textAAA))
        #expect(check.passes(.largeAAA))
    }

    @Test func theRatioIsRoundedDownSoAlmostPassingFails() {
        let check = ColorContrast(ratio: 4.499)
        #expect(check.ratioText == "4.49:1")
        #expect(!check.passes(.textAA))
        #expect(!check.passes(.largeAAA))
        #expect(ColorContrast(ratio: 2.999).ratioText == "2.99:1")
        #expect(!ColorContrast(ratio: 2.999).passes(.largeAA))
        #expect(!ColorContrast(ratio: 6.9999).passes(.textAAA))
        #expect(ColorContrast(ratio: 4.456).ratioText == "4.45:1")
    }

    @Test(arguments: [
        (ColorContrast.Level.textAA, 4.5), (.largeAA, 3), (.textAAA, 7), (.largeAAA, 4.5),
    ])
    func eachLevelPassesFromItsThreshold(level: ColorContrast.Level, threshold: Double) {
        #expect(ColorContrast(ratio: threshold).passes(level))
        #expect(!ColorContrast(ratio: threshold - 0.01).passes(level))
    }

    @Test func theLevelsAreNamedAsWCAGDoes() {
        #expect(ColorContrast.Level.allCases.map(\.title) == ["Text AA", "Large AA", "Text AAA", "Large AAA"])
    }
}
