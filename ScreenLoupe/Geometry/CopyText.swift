import CoreGraphics

/// Copy Text's placement and wording: where the text layer goes over the image, the pill while the
/// mode is on, and the toast after a copy.
enum CopyText {
    /// The text layer's frame in the image area's points, y down, over the frame's pixels as they
    /// show: `imageSize` pixels at `imageOrigin` in the picture, placed by `state` (drawable pixels,
    /// y down) and divided by `drawableScale`. The layer covers the whole frame, also where it
    /// reaches past the image area, so the recognised text sits on the pixels it was read from at
    /// any zoom and pan.
    static func overlayFrame(
        state: ZoomPanState, imageOrigin: CGPoint, imageSize: PixelSize, drawableScale: CGFloat
    ) -> CGRect {
        let scale = drawableScale > 0 ? drawableScale : 1
        let placed = state.imageRect(
            origin: imageOrigin, size: CGSize(width: imageSize.width, height: imageSize.height))
        return CGRect(
            x: placed.minX / scale, y: placed.minY / scale, width: placed.width / scale,
            height: placed.height / scale)
    }

    /// The pill that stands in for the Frozen or the recent capture's while the mode is on: "Text ·
    /// Frozen · Esc clears, then leaves" over the frozen live view, or "Text · Capture 2 of 8 · Esc
    /// clears, then leaves" with `picture`, the recent capture's or image file's name. The same
    /// whether text is selected or not.
    static func pillText(picture: String?) -> String {
        "Text · \(picture ?? "Frozen") · Esc clears, then leaves"
    }

    /// The toast when a picture can't be read: Live Text isn't supported on this Mac, or reading the
    /// picture failed. Without it the mode would show nothing and say nothing.
    static let unreadable = "Text can't be read here"

    /// The longest the copied text shows in the toast, in characters, the ellipsis included.
    static let toastLength = 32

    /// "“Continue” copied": the copied text on one line, runs of spaces and line breaks as one
    /// space, cut at the end with an ellipsis past `toastLength`. `nil` for text with nothing but
    /// spaces and line breaks, which isn't a text to copy.
    static func toast(for text: String) -> String? {
        let words = text.split { $0.isWhitespace || $0.isNewline }
        guard !words.isEmpty else { return nil }
        var line = words.joined(separator: " ")
        if line.count > toastLength {
            line = String(line.prefix(toastLength - 1))
            while line.last?.isWhitespace == true { line.removeLast() }
            line += "…"
        }
        return "“\(line)” copied"
    }
}
