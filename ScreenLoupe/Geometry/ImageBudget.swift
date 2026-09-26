import CoreGraphics

/// The largest image the app makes or loads (docs/design.md §2.4): 4096 × 4096 pixels, about 16
/// megapixels, and no side over Metal's texture limit. A copy, a saved file or a reference layer
/// that would be bigger keeps its top-left corner and is cropped, never scaled.
enum ImageBudget {
    static let side = 4096
    static let maxPixels = side * side
    /// Metal's largest texture side on every Mac the app runs on.
    static let maxSide = 16384

    /// The part of a `width` × `height` image that is kept, from its top-left corner. An image within
    /// the budget stays whole. Past it, a side shorter than 4096 stays and the other is cut to fit
    /// the budget; with both sides longer, 4096 × 4096 is kept.
    static func fitted(width: Int, height: Int) -> (width: Int, height: Int) {
        var w = min(width, maxSide)
        var h = min(height, maxSide)
        guard w * h > maxPixels else { return (w, h) }
        if w >= side, h >= side {
            (w, h) = (side, side)
        } else if w < side {
            h = maxPixels / w
        } else {
            w = maxPixels / h
        }
        return (w, h)
    }

    /// `size` (whole pixels) as `fitted` keeps it.
    static func fitted(_ size: CGSize) -> CGSize {
        let kept = fitted(width: Int(size.width.rounded()), height: Int(size.height.rounded()))
        return CGSize(width: kept.width, height: kept.height)
    }
}
