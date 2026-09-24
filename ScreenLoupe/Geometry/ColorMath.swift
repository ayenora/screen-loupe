import CoreGraphics
import Foundation

/// One screen pixel's colour: the value as captured, in the display's colour space, and the same
/// colour converted to sRGB for HEX/RGB (docs/design.md §4, Pixel Inspector).
struct ColorSample: Equatable, Sendable {
    /// Components 0...1 in the display's colour space, as captured.
    var native: (red: Double, green: Double, blue: Double)
    /// The display colour space's name, such as "Display P3".
    var nativeSpaceName: String
    /// Components 0...1 in sRGB, clamped: colours outside sRGB are clipped for HEX.
    var srgb: (red: Double, green: Double, blue: Double)

    static func == (a: ColorSample, b: ColorSample) -> Bool {
        a.native == b.native && a.nativeSpaceName == b.nativeSpaceName && a.srgb == b.srgb
    }

    /// Builds a sample from 8-bit components captured in `colorSpace`. `spaceName` overrides the name
    /// shown for it: a display's ICC-based space often has no system name.
    init(red: UInt8, green: UInt8, blue: UInt8, colorSpace: CGColorSpace, spaceName: String? = nil) {
        native = (Double(red) / 255, Double(green) / 255, Double(blue) / 255)
        nativeSpaceName = spaceName ?? Self.displayName(of: colorSpace)
        let components: [CGFloat] = [CGFloat(native.red), CGFloat(native.green), CGFloat(native.blue), 1]
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        if let color = CGColor(colorSpace: colorSpace, components: components),
            let converted = color.converted(to: sRGB, intent: .relativeColorimetric, options: nil),
            let values = converted.components, values.count >= 3
        {
            srgb = (Self.clamp(values[0]), Self.clamp(values[1]), Self.clamp(values[2]))
        } else {
            srgb = native
        }
    }

    init(srgbHex hex: String) {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        let components = (
            Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255
        )
        native = components
        nativeSpaceName = "sRGB"
        srgb = components
    }

    // MARK: Formats

    /// 8-bit sRGB components.
    var srgb8: (red: Int, green: Int, blue: Int) {
        (Self.byte(srgb.red), Self.byte(srgb.green), Self.byte(srgb.blue))
    }

    /// `#18191C`
    var hex: String {
        let c = srgb8
        return String(format: "#%02X%02X%02X", c.red, c.green, c.blue)
    }

    /// `rgb(24, 25, 28)`
    var cssRGB: String {
        let c = srgb8
        return "rgb(\(c.red), \(c.green), \(c.blue))"
    }

    /// `Color(red: 0.094, green: 0.098, blue: 0.110)` — SwiftUI, sRGB.
    var swiftUI: String {
        "Color(red: \(Self.decimal(srgb.red)), green: \(Self.decimal(srgb.green)), blue: \(Self.decimal(srgb.blue)))"
    }

    /// `NSColor(srgbRed: 0.094, green: 0.098, blue: 0.110, alpha: 1)` — AppKit; UIKit's is the same
    /// with `UIColor(red:…)`.
    var appKit: String {
        "NSColor(srgbRed: \(Self.decimal(srgb.red)), green: \(Self.decimal(srgb.green)), blue: \(Self.decimal(srgb.blue)), alpha: 1)"
    }

    /// `0.094 0.098 0.110` in the display's own colour space.
    var nativeValues: String {
        "\(Self.decimal(native.red)) \(Self.decimal(native.green)) \(Self.decimal(native.blue))"
    }

    // MARK: Contrast (WCAG 2.x)

    /// Relative luminance of the sRGB colour.
    var relativeLuminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(srgb.red) + 0.7152 * linear(srgb.green) + 0.0722 * linear(srgb.blue)
    }

    /// Contrast ratio between two colours, 1...21.
    static func contrastRatio(_ a: ColorSample, _ b: ColorSample) -> Double {
        let (l1, l2) = (a.relativeLuminance, b.relativeLuminance)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    // MARK: Helpers

    private static func clamp(_ value: CGFloat) -> Double { min(max(Double(value), 0), 1) }
    private static func byte(_ value: Double) -> Int { Int((value * 255).rounded()) }
    private static func decimal(_ value: Double) -> String { String(format: "%.3f", value) }

    private static func displayName(of colorSpace: CGColorSpace) -> String {
        guard let name = colorSpace.name.map({ $0 as String }) else { return "Display" }
        if name == CGColorSpace.displayP3 as String { return "Display P3" }
        if name == CGColorSpace.sRGB as String { return "sRGB" }
        return name.replacingOccurrences(of: "kCGColorSpace", with: "")
    }
}
