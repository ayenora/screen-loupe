import CoreGraphics
import Foundation

/// The window the Screenshot studio's One Window mode captures.
struct OneWindowChoice: Equatable, Sendable {
    var id: CGWindowID
    /// The owning app's name, shown beside the window's outline.
    var appName: String
}

/// The Screenshot studio's One Window mode: off, picking the
/// first window, picking another while one stays chosen, or on for one window. Kept for the session
/// only, never saved.
enum OneWindowMode: Equatable, Sendable {
    case off
    /// Picking the first window: none is chosen yet.
    case picking
    /// Pick Another Window: picking, while this window stays chosen until another is picked; a
    /// cancel goes back to it.
    case repicking(OneWindowChoice)
    case on(OneWindowChoice)

    enum Event: Equatable, Sendable {
        /// The palette's One Window button or the menu item.
        case toggle(studioVisible: Bool)
        /// Pick Another Window in the One Window list.
        case pickAnother
        /// End One Window in the One Window list.
        case end
        /// The picker's click on a window.
        case picked(OneWindowChoice)
        /// The picker ended without a window: Escape, a right click, a click on no window, another
        /// app becoming active.
        case cancelled
        /// Capture, Copy or Save pressed when a picture can be taken now (`OneWindowMode.press`).
        case pressed
        /// The studio was hidden.
        case hidden
        /// The chosen window can't be captured any more: no longer on screen here
        /// (`OneWindowWatch`), or found so by a press (`OneWindowPicture.shot`).
        case unavailable(OneWindowProblem)
    }

    /// The mode after `event`. Turning on needs the studio shown; the toggle and End One Window
    /// turn it off from any mode. A re-pick keeps the chosen window: its cancel, hiding the studio
    /// and a press go back to it, a pick replaces it. Hiding ends the first picking and keeps a
    /// chosen window, inert until the studio shows again; the chosen window becoming unavailable
    /// turns One Window off, re-picking or not.
    func after(_ event: Event) -> OneWindowMode {
        switch (self, event) {
        case (.off, .toggle(let visible)): visible ? .picking : .off
        case (_, .toggle), (_, .end): .off
        case (.on(let choice), .pickAnother): .repicking(choice)
        case (.picking, .picked(let choice)), (.repicking, .picked(let choice)): .on(choice)
        case (.picking, .cancelled), (.picking, .hidden): .off
        case (.repicking(let choice), .cancelled), (.repicking(let choice), .hidden),
            (.repicking(let choice), .pressed):
            .on(choice)
        case (.on, .unavailable), (.repicking, .unavailable): .off
        default: self
        }
    }

    /// The window a press captures and the outline marks: chosen, also while another is picked.
    var chosen: OneWindowChoice? {
        switch self {
        case .on(let choice), .repicking(let choice): choice
        case .off, .picking: nil
        }
    }

    /// The window picker runs: the first picking or a re-pick.
    var isPicking: Bool {
        switch self {
        case .picking, .repicking: true
        case .off, .on: false
        }
    }

    /// Whether the studio's frame is in use: shown, and what a picture is cut to; with it, Size, Fit
    /// to Window, Aspect Lock and Background, which set the frame and what lies under it. Only while
    /// One Window is off; otherwise the picture is the window alone, so the frame hides and comes
    /// back where it was when One Window ends, and those controls are disabled.
    var usesFrame: Bool { self == .off }

    /// Pick Another Window in the One Window list: enabled while a window is chosen and not
    /// already being replaced.
    var canPickAnother: Bool {
        if case .on = self { return true }
        return false
    }

    /// End One Window in the One Window list: enabled in every mode but off.
    var canEnd: Bool { self != .off }

    /// What a press of Capture, Copy or Save that can take a picture now does: the frame's picture
    /// while off, the chosen window's while one is chosen (a re-pick ends first, `.pressed`), and
    /// none during the first picking.
    var press: OneWindowPress {
        switch self {
        case .off: .frame
        case .picking: .pickFirst
        case .repicking(let choice), .on(let choice): .window(choice)
        }
    }

    /// The line on top of Screenshot › Size and Screenshot › Background while the frame isn't in
    /// use (`usesFrame`), above their disabled items.
    static let frameControlsNote = "Not used in One Window: the picture is the window alone, on transparency."
}

/// What a press that can take a picture now takes (`OneWindowMode.press`).
enum OneWindowPress: Equatable, Sendable {
    case frame
    case window(OneWindowChoice)
    /// Nothing: no window is chosen yet. The press is refused with "Pick a window first", the
    /// picking goes on.
    case pickFirst

    static let pickFirstNotice = "Pick a window first"
}

/// Reads of the chosen window's place, about 60 a second while the studio shows: where its outline goes, and when One
/// Window lets the window go. The magnet's
/// rules (`WindowMagnet.holds`, `readsToLetGo`) at its pace (`WindowMagnet.readInterval`): a window
/// closed, minimised, hidden with its app or on another Space reads as not held, and two such reads
/// in a row let it go.
struct OneWindowWatch: Equatable, Sendable {
    enum Outcome: Equatable, Sendable {
        /// On screen, at this frame in AppKit global coordinates: the outline goes there.
        case shows(CGRect)
        /// One odd read: the outline stays where it was.
        case unsure
        /// Gone from the screen: One Window turns off (`OneWindowProblem.notListed`).
        case unavailable
    }

    /// Reads in a row that didn't hold the window.
    private(set) var badReads = 0

    /// The outcome of one read of the list, `nil` when it doesn't list the window at all.
    mutating func read(_ window: ScreenWindow?) -> Outcome {
        guard let window, WindowMagnet.holds(window) else {
            badReads += 1
            return WindowMagnet.letsGo(afterBadReads: badReads) ? .unavailable : .unsure
        }
        badReads = 0
        return .shows(window.frame)
    }
}

/// Where the chosen window's outline and its app's name go, in
/// AppKit global coordinates: the line just outside the window's frame, so it covers none of the
/// window, and the label at the outline's top-left, above it, or inside its top-left corner when
/// the screen has no room above.
struct OneWindowOutline: Equatable, Sendable {
    /// The outline's panel: the line with its halo and the label.
    var panel: CGRect
    /// The rect the line is drawn around, its halo outside it: the window grown by the line width.
    var line: CGRect
    var label: CGRect
    var labelInside: Bool

    /// The outline of a window at `window`, a line of `lineWidth` points and a label of `labelSize`,
    /// kept on `screen` (the visible frame of the window's display): the label never covers the
    /// menu bar or leaves the screen sideways.
    init(window: CGRect, lineWidth: CGFloat, labelSize: CGSize, screen: CGRect, metrics m: OverlayMetrics = .standard) {
        line = window.insetBy(dx: -lineWidth, dy: -lineWidth)
        let aboveY = line.maxY + m.labelGap
        labelInside = aboveY + labelSize.height > screen.maxY - m.screenMargin
        let x = labelInside ? window.minX + m.labelGap : line.minX
        let y = labelInside ? min(window.maxY, screen.maxY) - m.labelGap - labelSize.height : aboveY
        let clampedX = min(max(x, screen.minX + m.screenMargin), screen.maxX - m.screenMargin - labelSize.width)
        label = CGRect(
            x: clampedX.rounded(), y: y.rounded(), width: labelSize.width, height: labelSize.height)
        panel = line.insetBy(dx: -m.haloWidth, dy: -m.haloWidth).union(label)
    }
}

/// Why the chosen window can't be captured alone: One Window turns off, the frame comes back, and
/// no picture is taken.
enum OneWindowProblem: Error, Equatable, Sendable {
    /// Not among the on-screen windows: closed, minimised, hidden, on another Space, gone full
    /// screen.
    case notListed
    /// Its pixels aren't its display's: it would have to be scaled.
    case otherScale

    /// What losing the window says, with a beep, beside the frame's tab, the frame back on screen:
    /// nothing when the loss `cancels` nothing — the window closed or hidden while nothing waited
    /// for it — and nothing while the studio is hidden, where a capture or countdown is simply
    /// dropped; otherwise, when it cancels a running countdown or a pressed Capture, Copy or Save,
    /// why nothing was captured.
    func notice(cancels: Bool, studioVisible: Bool) -> String? {
        guard cancels, studioVisible else { return nil }
        return switch self {
        case .notListed: "Window gone · nothing captured"
        case .otherScale: "Window can't be captured · nothing captured"
        }
    }
}

/// What a press takes while a window is chosen (`OneWindowPicture.shot`).
enum OneWindowShot: Equatable, Sendable {
    case window
    /// Nothing: the window can't be captured unscaled, or at all.
    case unavailable(OneWindowProblem)
}

/// How a lone window's capture becomes a picture: captured with
/// room to spare, then cut to its visible pixels — the window and, when captured, its shadow —
/// at its native pixels, never scaled. Nothing is laid under it: around the window and through
/// its shadow the picture is transparent.
enum OneWindowPicture {
    /// Points of room on every side of the window for the capture's output: more than the largest
    /// shadow macOS draws (the active window's), so the window with its shadow is never scaled
    /// down to the output.
    static let room: CGFloat = 128

    /// Points on each side of an axis a capture may leave empty and still count as filling it: a
    /// capture scaled down fills the output on at least one axis, but the faintest pixels of its
    /// shadow may round to nothing. Well under `room` minus the largest shadow, so a capture at its
    /// own size never counts.
    static let fillTolerance: CGFloat = 16

    /// The capture's output size for a window of `window` pixels at `scale` pixels per point.
    static func captureSize(window: PixelSize, scale: CGFloat) -> PixelSize {
        let pixels = Int((room * scale).rounded(.up))
        return PixelSize(width: window.width + 2 * pixels, height: window.height + 2 * pixels)
    }

    /// Whether a capture of `capture` pixels at `scale` whose visible pixels are `visible` came
    /// scaled down: they fill an axis of the output, where a window at its own size leaves room.
    static func isScaledDown(visible: PixelSize, capture: PixelSize, scale: CGFloat) -> Bool {
        let slack = 2 * Int((fillTolerance * scale).rounded(.up))
        return visible.width > capture.width - slack || visible.height > capture.height - slack
    }

    /// What a press takes for a window listed on screen at `windowScale` pixels per point (`nil`
    /// when it isn't listed on screen at all) on a display of `displayScale` — the display holding
    /// most of the window, whose pixels the picture is in: the window, or, when it can't be captured
    /// unscaled, nothing, One Window released.
    static func shot(windowScale: CGFloat?, displayScale: CGFloat) -> OneWindowShot {
        guard let windowScale else { return .unavailable(.notListed) }
        return windowScale == displayScale ? .window : .unavailable(.otherScale)
    }

    /// The smallest rect holding every pixel of `image` that isn't wholly transparent — the window
    /// and, when captured, its shadow; `nil` when every pixel is. An image without alpha is opaque
    /// throughout.
    static func visibleBounds(of image: CGImage) -> PixelRect? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        // Premultiplied BGRA in memory: alpha is each pixel's fourth byte. In the image's own space,
        // so nothing is converted, or in sRGB when that space can't hold BGRA; alpha is the same.
        func context(in space: CGColorSpace?) -> CGContext? {
            space.flatMap {
                CGContext(
                    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: $0,
                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            }
        }
        guard
            let context = context(in: image.colorSpace) ?? context(in: CGColorSpace(name: CGColorSpace.sRGB)),
            let data = context.data
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bytesPerRow = context.bytesPerRow
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        // The context's first row is the image's top row.
        for y in 0..<height {
            let row = bytes + y * bytesPerRow + 3
            var x = 0
            while x < width, row[x * 4] == 0 { x += 1 }
            guard x < width else { continue }
            var last = width - 1
            while row[last * 4] == 0 { last -= 1 }
            minX = min(minX, x)
            maxX = max(maxX, last)
            if minY == height { minY = y }
            maxY = y
        }
        guard maxX >= 0 else { return nil }
        return PixelRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
