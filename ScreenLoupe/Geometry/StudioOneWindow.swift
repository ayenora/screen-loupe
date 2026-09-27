import CoreGraphics

/// The window the Screenshot studio's One Window mode captures.
struct OneWindowChoice: Equatable, Sendable {
    var id: CGWindowID
    /// The owning app's name, shown in the frame's tab.
    var appName: String
}

/// The Screenshot studio's One Window mode (docs/product.md, Screenshot studio): off, picking the
/// window, or on for one window. Kept for the session only, never saved.
enum OneWindowMode: Equatable, Sendable {
    case off
    case picking
    case on(OneWindowChoice)

    enum Event: Equatable, Sendable {
        /// The palette's One Window button or the menu item.
        case toggle(studioVisible: Bool)
        /// The picker's click on a window.
        case picked(OneWindowChoice)
        /// The picker ended without a window: Escape, a right click, a click on no window, another
        /// app becoming active.
        case cancelled
        /// The studio was hidden.
        case hidden
        /// The numbers of every window that exists now, on screen or not.
        case checked(existing: Set<CGWindowID>)
    }

    /// The mode after `event`. Turning on needs the studio shown; hiding ends picking but keeps a
    /// chosen window, inert until the studio shows again; the chosen window closing turns it off.
    func after(_ event: Event) -> OneWindowMode {
        switch (self, event) {
        case (.off, .toggle(let visible)): visible ? .picking : .off
        case (.picking, .toggle), (.on, .toggle): .off
        case (.picking, .picked(let choice)): .on(choice)
        case (.picking, .cancelled), (.picking, .hidden): .off
        case (.on(let choice), .checked(let existing)): existing.contains(choice.id) ? self : .off
        default: self
        }
    }

    var chosen: OneWindowChoice? {
        if case .on(let choice) = self { return choice }
        return nil
    }

    var isPicking: Bool { self == .picking }

    /// Added to the frame's tab while a window is chosen.
    var tabNote: String? { chosen.map { "One window: \($0.appName)" } }
}

/// A rect of whole pixels in an image, origin at its top-left corner, y down.
struct PixelRect: Equatable, Sendable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int

    var size: PixelSize { PixelSize(width: width, height: height) }
}

/// How a lone window's capture becomes a picture (docs/design.md, Screenshot studio): captured with
/// room to spare, cut to its visible pixels, and centred on whole pixels in a picture of the frame's
/// size, grown where the window with its shadow needs more, never scaled.
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

    /// Whether a window of `size` pixels fits a frame of `frame` pixels: equal fits, one pixel over
    /// in either axis doesn't.
    static func fits(_ size: PixelSize, in frame: PixelSize) -> Bool {
        size.width <= frame.width && size.height <= frame.height
    }

    /// The picture's size for a frame of `frame` pixels and a window whose visible pixels, its
    /// shadow's among them, are `visible`: the frame's, grown on each axis only as far as `visible`
    /// needs. The frame on screen stays as it is.
    static func pictureSize(frame: PixelSize, visible: PixelSize) -> PixelSize {
        PixelSize(width: max(frame.width, visible.width), height: max(frame.height, visible.height))
    }

    /// The top-left corner, in whole pixels from the frame's top-left, of a picture of `size`
    /// centred in `frame`. An odd pixel left over goes right of it and below it; in a picture
    /// grown to `size` (`pictureSize`), that axis starts at 0.
    static func centredOrigin(of size: PixelSize, in frame: PixelSize) -> (x: Int, y: Int) {
        ((frame.width - size.width) / 2, (frame.height - size.height) / 2)
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
