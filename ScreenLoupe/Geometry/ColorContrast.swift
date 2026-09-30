import Foundation

/// The WCAG 2 contrast of a text colour on a background, as the Color Meter's Contrast shows it.
///
/// The ratio is kept in hundredths rounded down, and the verdicts are read from that same value, so
/// 4.499 shows as 4.49 and fails 4.5: what shows never passes when the ratio doesn't.
struct ColorContrast: Equatable {
    enum Level: CaseIterable {
        case textAA, largeAA, textAAA, largeAAA

        var title: String {
            switch self {
            case .textAA: "Text AA"
            case .largeAA: "Large AA"
            case .textAAA: "Text AAA"
            case .largeAAA: "Large AAA"
            }
        }

        /// The lowest ratio that passes, in hundredths.
        var minimum: Int {
            switch self {
            case .textAA, .largeAAA: 450
            case .largeAA: 300
            case .textAAA: 700
            }
        }
    }

    /// The ratio × 100, rounded down: 1...2100.
    let hundredths: Int

    /// Opacity is left out: the ratio is of the sRGB values.
    init(text: ColorSample, background: ColorSample) {
        self.init(ratio: ColorSample.contrastRatio(text, background))
    }

    init(ratio: Double) {
        // The tolerance keeps a ratio that is exactly 21 or 4.5 on paper from flooring below it
        // through binary rounding; it is far smaller than the 8-bit steps between real ratios.
        hundredths = Int((ratio * 100 + 1e-9).rounded(.down))
    }

    /// "4.49:1".
    var ratioText: String { String(format: "%d.%02d:1", hundredths / 100, hundredths % 100) }

    func passes(_ level: Level) -> Bool { hundredths >= level.minimum }
}
