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
    /// Opacity 0...1, straight: 1 for the screen, an opened image's own (docs/product.md, Open Image).
    var alpha: Double

    static func == (a: ColorSample, b: ColorSample) -> Bool {
        a.native == b.native && a.nativeSpaceName == b.nativeSpaceName && a.srgb == b.srgb && a.alpha == b.alpha
    }

    /// Builds a sample from 8-bit components captured in `colorSpace`, not premultiplied. `spaceName`
    /// overrides the name shown for it: a display's ICC-based space often has no system name.
    init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255, colorSpace: CGColorSpace, spaceName: String? = nil)
    {
        native = (Double(red) / 255, Double(green) / 255, Double(blue) / 255)
        self.alpha = Double(alpha) / 255
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

    /// `#RRGGBB`, or `#RRGGBBAA` with an opacity.
    init(srgbHex hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value = UInt32(digits, radix: 16) ?? 0
        alpha = 1
        if digits.count == 8 {
            alpha = Double(value & 0xFF) / 255
            value >>= 8
        }
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

    /// Whether the colour is not fully opaque; only then do the formats name the opacity.
    var isTranslucent: Bool { alpha < 1 }

    /// `#18191C`, or `#18191C80` when translucent.
    var hex: String {
        let c = srgb8
        let rgb = String(format: "#%02X%02X%02X", c.red, c.green, c.blue)
        return isTranslucent ? rgb + String(format: "%02X", Self.byte(alpha)) : rgb
    }

    /// `rgb(24, 25, 28)`, or `rgba(24, 25, 28, 0.502)` when translucent.
    var cssRGB: String {
        let c = srgb8
        guard isTranslucent else { return "rgb(\(c.red), \(c.green), \(c.blue))" }
        return "rgba(\(c.red), \(c.green), \(c.blue), \(Self.decimal(alpha)))"
    }

    /// `Color(red: 0.094, green: 0.098, blue: 0.110)` — SwiftUI, sRGB; with `opacity:` when translucent.
    var swiftUI: String {
        let opacity = isTranslucent ? ", opacity: \(Self.decimal(alpha))" : ""
        return
            "Color(red: \(Self.decimal(srgb.red)), green: \(Self.decimal(srgb.green)), blue: \(Self.decimal(srgb.blue))\(opacity))"
    }

    /// `NSColor(srgbRed: 0.094, green: 0.098, blue: 0.110, alpha: 1)` — AppKit; UIKit's is the same
    /// with `UIColor(red:…)`.
    var appKit: String {
        let opacity = isTranslucent ? Self.decimal(alpha) : "1"
        return
            "NSColor(srgbRed: \(Self.decimal(srgb.red)), green: \(Self.decimal(srgb.green)), blue: \(Self.decimal(srgb.blue)), alpha: \(opacity))"
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

extension CGColorSpace {
    /// The colour space an opened image's pixels are kept in, as 8-bit BGRA like a captured frame
    /// (docs/design.md §2): the image's own when it is RGB, and a palette's RGB base for an indexed
    /// one, so the values stay as they are; sRGB for anything else (gray, CMYK, an extended-range
    /// space of a float image, which 8 bits can't hold), which is converted.
    /// ImageIO already gives an image without a profile sRGB.
    static func rgbSpace(forImageIn space: CGColorSpace?) -> CGColorSpace {
        let rgb = space?.model == .indexed ? space?.baseColorSpace : space
        guard let rgb, rgb.model == .rgb, !CGColorSpaceUsesExtendedRange(rgb) else {
            return CGColorSpace(name: CGColorSpace.sRGB)!
        }
        return rgb
    }
}
