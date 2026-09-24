import CoreGraphics

/// The size strings shown on the Capture Area frame.
enum SizeText {
    /// `220 × 150`: points, with one decimal when the size sits on a half-point (2× displays).
    static func points(_ size: CGSize) -> String {
        "\(number(size.width)) × \(number(size.height))"
    }

    /// `220 × 150 pt · 440 × 300 px`.
    static func pointsAndPixels(_ size: CGSize, scale: CGFloat) -> String {
        let pixels = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        return "\(points(size)) pt · \(points(pixels)) px"
    }

    private static func number(_ value: CGFloat) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%.1f", Double(rounded))
    }
}
