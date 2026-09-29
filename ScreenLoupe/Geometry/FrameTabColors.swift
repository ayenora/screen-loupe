import CoreGraphics
import Foundation

/// The frame tab's fill and whether its text and grip are white, from the frame's sRGB accent
/// (docs/design.md §4, Capture Area frame). The tab is the accent at 78%. White goes on it when it
/// reaches 4.5:1 there, or on a tab darkened in steps of 2% down to 70% of the accent: WCAG 2 rates
/// black higher on mid oranges, where white reads better. Otherwise black goes on the 78% tab.
struct FrameTabColors: Equatable {
    /// The tab's sRGB components, 0...1.
    var red: Double
    var green: Double
    var blue: Double
    var textIsWhite: Bool

    /// The tab's share of the accent.
    static let tabShare = 0.78
    /// The darkest the tab goes for white text, and the step down to it.
    static let darkestShare = 0.70
    static let shareStep = 0.02
    /// WCAG 2's AA ratio for normal text.
    static let minimumContrast = 4.5

    init(accentRed: Double, green accentGreen: Double, blue accentBlue: Double) {
        func tab(_ share: Double) -> (Double, Double, Double) {
            (accentRed * share, accentGreen * share, accentBlue * share)
        }
        // 78%, 76%, … 70%.
        let steps = Int(((Self.tabShare - Self.darkestShare) / Self.shareStep).rounded())
        for step in 0...steps {
            let darkened = tab(Self.tabShare - Self.shareStep * Double(step))
            if Self.contrastWithWhite(darkened) >= Self.minimumContrast {
                (red, green, blue) = darkened
                textIsWhite = true
                return
            }
        }
        (red, green, blue) = tab(Self.tabShare)
        textIsWhite = false
    }

    /// Rounded to 8-bit components, as drawn.
    private static func contrastWithWhite(_ color: (Double, Double, Double)) -> Double {
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        func byte(_ value: Double) -> UInt8 { UInt8((min(max(value, 0), 1) * 255).rounded()) }
        let sample = ColorSample(red: byte(color.0), green: byte(color.1), blue: byte(color.2), colorSpace: sRGB)
        return ColorSample.contrastRatio(sample, ColorSample(red: 255, green: 255, blue: 255, colorSpace: sRGB))
    }
}
