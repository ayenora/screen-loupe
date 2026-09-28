import CoreGraphics

/// The pixel density a pasted image carries, and the size it gives the image as a reference layer
/// (docs/product.md, Dropping and pasting images). An image marked 72, 144 or 216 pixels per inch
/// is taken as 1×, 2× or 3×: 72 pixels per inch is one pixel for each point of 1/72 inch.
enum PixelDensity {
    /// Points per inch: one image pixel per point at 72 pixels per inch.
    static let pointsPerInch: Double = 72
    /// The densities taken: 1×, 2× and 3×.
    static let pixelsPerPointRange = 1...3
    /// How far a resolution may be from a whole multiple of 72, for one stored in pixels per metre.
    static let tolerance: Double = 0.5

    /// Image pixels per point from its horizontal and vertical resolution in pixels per inch: 72 is
    /// 1×, 144 is 2×, 216 is 3×. Only one of them known is enough. `nil` when neither is known,
    /// when they differ, or for any other resolution — 96, 300 or a fraction of a multiple — which
    /// says nothing about a screen.
    static func pixelsPerPoint(dpiWidth: Double?, dpiHeight: Double?) -> Int? {
        let known = [dpiWidth, dpiHeight].compactMap { $0 }
        guard let dpi = known.first, known.allSatisfy({ abs($0 - dpi) <= tolerance }) else { return nil }
        guard dpi.isFinite, dpi > 0 else { return nil }
        let multiple = (dpi / pointsPerInch).rounded()
        guard abs(dpi - multiple * pointsPerInch) <= tolerance, let whole = Int(exactly: multiple),
            pixelsPerPointRange.contains(whole)
        else { return nil }
        return whole
    }

    /// Pixels per point of the display a pasted image is placed for: the one the stream captures,
    /// else the one the Capture Area is on, which the stream is about to capture — while it starts,
    /// or moves to another display. `nil` when neither is known (no access, the area on no display).
    static func sourceScale(stream: CGFloat?, area: CGFloat?) -> CGFloat? {
        stream ?? area
    }

    /// A pasted reference layer's scale, source pixels per image pixel: the capturing display's
    /// pixels per point over the image's, so the image covers as many points on the screen as it
    /// was made for — a 2× image one to one on a Retina display, a 1× image doubled. `nil` for
    /// either keeps it one image pixel per source pixel, as a dropped file is.
    static func referenceScale(pixelsPerPoint: Int?, sourceScale: CGFloat?) -> CGFloat {
        guard let pixelsPerPoint, pixelsPerPoint > 0, let sourceScale, sourceScale.isFinite, sourceScale > 0
        else { return 1 }
        return sourceScale / CGFloat(pixelsPerPoint)
    }
}
