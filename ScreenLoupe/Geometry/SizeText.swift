import CoreGraphics

/// Which units the frame's size strings show (Settings › Capture Area).
enum SizeUnits: String, Codable, CaseIterable, Sendable {
    case pointsAndPixels, points, pixels
}

/// The size strings shown on the Capture Area frame.
enum SizeText {
    /// `220 × 150`: points, with one decimal when the size sits on a half-point (2× displays).
    static func points(_ size: CGSize) -> String {
        "\(number(size.width)) × \(number(size.height))"
    }

    /// `220 × 150 pt · 440 × 300 px`.
    static func pointsAndPixels(_ size: CGSize, scale: CGFloat) -> String {
        "\(points(size)) pt · \(points(pixels(size, scale: scale))) px"
    }

    /// The grip tab: `220 × 150 pt · 440 × 300 px`, `220 × 150 pt` or `440 × 300 px`.
    static func tab(_ size: CGSize, scale: CGFloat, units: SizeUnits) -> String {
        switch units {
        case .pointsAndPixels: pointsAndPixels(size, scale: scale)
        case .points: "\(points(size)) pt"
        case .pixels: "\(points(pixels(size, scale: scale))) px"
        }
    }

    /// The muted label at rest, without units: points, or pixels when only pixels are chosen.
    static func label(_ size: CGSize, scale: CGFloat, units: SizeUnits) -> String {
        units == .pixels ? points(pixels(size, scale: scale)) : points(size)
    }

    /// The L T R B box: the edges of `rect` (display-local points, top-left origin) in points, or in
    /// pixels when only pixels are chosen.
    static func edges(_ rect: CGRect, scale: CGFloat, units: SizeUnits) -> [(key: String, value: String)] {
        let factor = units == .pixels ? scale : 1
        return [("L", rect.minX), ("T", rect.minY), ("R", rect.maxX), ("B", rect.maxY)].map {
            (key: $0.0, value: number(($0.1 * factor * 10).rounded() / 10))
        }
    }

    private static func pixels(_ size: CGSize, scale: CGFloat) -> CGSize {
        CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }

    private static func number(_ value: CGFloat) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%.1f", Double(rounded))
    }
}
