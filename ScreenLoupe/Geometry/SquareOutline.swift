import CoreGraphics

/// How the Viewer outlines a probe's square of pixels (`PixelInspector.Probe.square`): the square,
/// and the pointed pixel in a thin line inside it while a pixel is large enough to show one.
enum SquareOutline {
    /// The smallest side of a pixel on screen, in points, that gets its own outline: below it the
    /// line, half a point inside the pixel, would cover it or vanish, and the square alone shows.
    static let minimumPixelSide: CGFloat = 4

    /// Whether the pointed pixel, `side` points wide on screen, is outlined inside the square.
    static func outlinesPixel(side: CGFloat) -> Bool { side >= minimumPixelSide }
}
