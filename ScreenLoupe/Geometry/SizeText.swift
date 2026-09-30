import CoreGraphics

/// Which units the frame's size strings show (Settings › Capture Area).
enum SizeUnits: String, Codable, CaseIterable, Sendable {
    case pointsAndPixels, points, pixels
}

/// The size strings shown on the frames, and the pixel and point pair every size in the app uses.
enum SizeText {
    /// `220 × 150`: points, with one decimal when the size sits on a half-point (2× displays).
    static func points(_ size: CGSize) -> String {
        "\(number(size.width)) × \(number(size.height))"
    }

    /// A length or size in pixels and in points, `first · second` (`32 px · 16 pt`,
    /// `220 × 150 pt · 440 × 300 px`), or one of them where a pixel is a point (`scale` 1: a 1×
    /// display, an image file) and both would give the same number: `first`, or `second` with
    /// `keepsSecond`. Every pixel and point pair the app shows goes through here.
    static func pair(_ first: String, _ second: String, scale: CGFloat, keepsSecond: Bool = false) -> String {
        guard scale != 1 else { return keepsSecond ? second : first }
        return "\(first) · \(second)"
    }

    /// `220 × 150 pt · 440 × 300 px`; one of them where a pixel is a point (`pair`): `220 × 150 pt`,
    /// or `220 × 150 px` with `keepsPixels`.
    static func pointsAndPixels(_ size: CGSize, scale: CGFloat, keepsPixels: Bool = false) -> String {
        pair("\(points(size)) pt", "\(points(pixels(size, scale: scale))) px", scale: scale, keepsSecond: keepsPixels)
    }

    /// The grip tab: `220 × 150 pt · 440 × 300 px`, `220 × 150 pt` or `440 × 300 px`. Both units give
    /// one size where a pixel is a point: in points, or in pixels with `keepsPixels` (a frame whose
    /// sizes are chosen in pixels, the Screenshot studio's).
    static func tab(_ size: CGSize, scale: CGFloat, units: SizeUnits, keepsPixels: Bool = false) -> String {
        switch units {
        case .pointsAndPixels: pointsAndPixels(size, scale: scale, keepsPixels: keepsPixels)
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

    /// `12`, or `12.5` on a half: one decimal at most.
    static func number(_ value: CGFloat) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%.1f", Double(rounded))
    }
}
