import CoreGraphics

/// The Screenshot studio's backdrop (docs/design.md, Screenshot studio): a window covering the
/// whole display the studio's frame is on, above the wallpaper and the desktop icons and below
/// every other window, showing the chosen background. The picture then is plain what the frame
/// shows.
enum StudioBackdrop {
    /// What the backdrop shows, and where: the background over `display`, drawn at `pixelSize`.
    struct Placement: Equatable, Sendable {
        var display: DisplayInfo
        var background: StudioBackground
        /// The whole display in its backing pixels.
        var pixelSize: PixelSize
    }

    /// Where the backdrop shows: on the display holding the larger share of `frame`, the one the
    /// studio captures from (`DisplayCoordinateConverter.owningDisplay`). `nil` — no backdrop —
    /// while the studio is hidden, with the screen as its background, or with the frame on no
    /// display.
    static func placement(
        studioVisible: Bool, background: StudioBackground, frame: GlobalRect, converter: DisplayCoordinateConverter?
    ) -> Placement? {
        guard studioVisible, background != .screen, let display = converter?.owningDisplay(for: frame) else {
            return nil
        }
        return Placement(display: display, background: background, pixelSize: pixelSize(of: display))
    }

    /// The whole of `display` in its backing pixels.
    static func pixelSize(of display: DisplayInfo) -> PixelSize {
        PixelSize(
            width: Int((display.globalFrame.width * display.scale).rounded()),
            height: Int((display.globalFrame.height * display.scale).rounded()))
    }
}
