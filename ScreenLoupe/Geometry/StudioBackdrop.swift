import CoreGraphics

/// The Screenshot studio's backdrop: a window covering the
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

    /// The menu bar's height over a screen of `frame` whose `visible` frame is below it, both in
    /// AppKit's coordinates: 0 with no menu bar on that screen, or one that hides itself.
    static func menuBarHeight(frame: CGRect, visible: CGRect) -> CGFloat {
        max(0, frame.maxY - visible.maxY)
    }

    /// The grey of the strip under the menu bar, in sRGB: white and black symbols on it are equally
    /// legible, as the menu bar's are white or black by the wallpaper, not by the backdrop. Its
    /// relative luminance is √(1.05 × 0.05) − 0.05, where both contrasts are 4.58:1.
    static let menuBarGray: CGFloat = 118 / 255

    /// A backdrop picture: the placement, drawn in `space`, its display's colour space.
    struct Target: Equatable {
        var placement: Placement
        var space: CGColorSpace
    }

    /// What the backdrop shows, what was last asked for and which drawing is the latest: decides
    /// when a picture is drawn, when the backdrop hides at once, and which finished drawing shows.
    /// A picture is drawn only when the background, the display, its scale or its colour space
    /// change; for another display the old picture goes at once rather than showing stretched
    /// there; for another background it stays until the new one is drawn.
    struct Tracker {
        /// What the backdrop shows; `nil` while it is hidden.
        private(set) var shown: Target?
        /// What the latest picture was asked for: while it is drawn, and after it failed, so a
        /// failure isn't tried again, and beeped about, on every move of the frame.
        private(set) var asked: Target?
        /// Counts the pictures asked for: only the latest is shown.
        private(set) var request = 0

        enum Update: Equatable {
            /// Nothing to do: what is wanted shows, or is being drawn.
            case none
            /// Hide the backdrop now.
            case hide
            /// Draw `target` as drawing number `request`, hiding the backdrop first when `hidesFirst`.
            case render(Target, request: Int, hidesFirst: Bool)
        }

        enum Finish: Equatable {
            /// A newer picture was asked for meanwhile: this one is dropped.
            case stale
            /// It couldn't be drawn; the backdrop hides when `hides`.
            case failed(hides: Bool)
            /// It shows; `announces` when the backdrop wasn't showing before.
            case shown(announces: Bool)
        }

        /// The backdrop should show `wanted`, `nil` for none.
        mutating func update(wanted: Target?) -> Update {
            guard let wanted else {
                request += 1
                asked = nil
                return hide() ? .hide : .none
            }
            if shown == wanted {
                // Back to what shows: a picture still drawn for another background must not replace it.
                if asked != nil {
                    request += 1
                    asked = nil
                }
                return .none
            }
            if asked == wanted { return .none }
            let hidesFirst =
                shown.map { $0.placement.display.globalFrame != wanted.placement.display.globalFrame } ?? false
            if hidesFirst { shown = nil }
            request += 1
            asked = wanted
            return .render(wanted, request: request, hidesFirst: hidesFirst)
        }

        /// Drawing number `request` finished, with a picture when `drawn`.
        mutating func finished(_ request: Int, drawn: Bool) -> Finish {
            guard request == self.request, let asked else { return .stale }
            guard drawn else { return .failed(hides: hide()) }
            let announces = shown == nil
            shown = asked
            return .shown(announces: announces)
        }

        /// Whether a shown backdrop goes.
        private mutating func hide() -> Bool {
            guard shown != nil else { return false }
            shown = nil
            return true
        }
    }
}
