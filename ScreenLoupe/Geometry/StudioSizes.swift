import CoreGraphics
import Foundation

/// A size of the user's own for the Screenshot studio's frame, in whole pixels, with an optional
/// name (docs/product.md, Screenshot studio).
struct CustomSize: Codable, Equatable, Sendable {
    var name = ""
    var width: Int
    var height: Int

    var pixels: PixelSize { PixelSize(width: width, height: height) }

    init(name: String = "", width: Int, height: Int) {
        self.name = name
        self.width = width
        self.height = height
    }

    /// The name is optional in saved data: without it the size still loads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        width = try c.decode(Int.self, forKey: .width)
        height = try c.decode(Int.self, forKey: .height)
    }
}

/// What applying a size to the studio's frame gives (`StudioSizes.frame`).
enum StudioSizeFit: Equatable, Sendable {
    case fits(CGRect)
    /// Wider or taller than the frame's display: not applied.
    case largerThanDisplay
    /// Under the frame's minimum on its display: not applied.
    case smallerThanMinimum
}

/// The sizes the studio's frame can take, and applying one (docs/product.md, Screenshot studio).
enum StudioSizes {
    static let appStore = [
        PixelSize(width: 1280, height: 800), PixelSize(width: 1440, height: 900),
        PixelSize(width: 2560, height: 1600), PixelSize(width: 2880, height: 1800),
    ]
    static let web = [PixelSize(width: 1200, height: 630), PixelSize(width: 1920, height: 1080)]

    /// The longest side a typed size may have: Metal's texture limit, far beyond any display.
    static let maximumSide = 16384

    static func isValid(width: Int, height: Int) -> Bool {
        (1...maximumSide).contains(width) && (1...maximumSide).contains(height)
    }

    /// A size typed as text in W and H fields: whole pixels, spaces around them ignored; `nil`
    /// unless both parse and the size is valid.
    static func parse(width: String, height: String) -> PixelSize? {
        guard let width = Int(width.trimmingCharacters(in: .whitespaces)),
            let height = Int(height.trimmingCharacters(in: .whitespaces)),
            isValid(width: width, height: height)
        else { return nil }
        return PixelSize(width: width, height: height)
    }

    /// One of the presets. A custom size equal to one is checked in the lists only as the preset.
    static func isPreset(_ size: PixelSize) -> Bool {
        appStore.contains(size) || web.contains(size)
    }

    /// Whether a list entry for `size` is checked with the frame at `current`. A custom size equal to
    /// a preset is checked only as the preset, so one entry is checked at most once per size.
    static func isChecked(_ size: PixelSize, isPresetEntry: Bool, current: PixelSize?) -> Bool {
        size == current && (isPresetEntry || !isPreset(size))
    }

    /// `1280 × 800 px`.
    static func title(_ size: PixelSize) -> String {
        "\(size.width) × \(size.height) px"
    }

    /// `Hero · 1600 × 1000 px`, or `1600 × 1000 px` without a name.
    static func title(_ size: CustomSize) -> String {
        let name = size.name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? title(size.pixels) : "\(name) · \(title(size.pixels))"
    }

    /// The frame `rect` (AppKit global points, on `display`'s pixel grid) resized to `size` pixels of
    /// `display`, keeping its top-left corner, then moved back onto the display as little as needed.
    /// A size the display can't hold, or one under `minimumSize` points, isn't applied: the studio
    /// never takes a picture of another size than the one asked for.
    static func frame(
        _ rect: CGRect, resizedTo size: PixelSize, on display: DisplayInfo, minimumSize: CGSize
    )
        -> StudioSizeFit
    {
        let width = CGFloat(size.width) / display.scale
        let height = CGFloat(size.height) / display.scale
        let bounds = display.globalFrame
        if width > bounds.width || height > bounds.height { return .largerThanDisplay }
        if width < minimumSize.width || height < minimumSize.height { return .smallerThanMinimum }
        // y up: the top-left corner is (minX, maxY).
        let x = min(max(rect.minX, bounds.minX), bounds.maxX - width)
        let top = max(min(rect.maxY, bounds.maxY), bounds.minY + height)
        return .fits(CGRect(x: x, y: top - height, width: width, height: height))
    }

    // MARK: Custom sizes

    /// The slots of the Custom Sizes window: the filled ones first, in order, then empty ones.
    static let slotCount = 4

    /// Saved sizes as the studio uses them: the valid ones, at most `slotCount`.
    /// Saved data is read element by element (`decodeCustomSizes`), so one bad slot costs only itself.
    static func sanitized(_ sizes: [CustomSize]) -> [CustomSize] {
        Array(sizes.filter { isValid(width: $0.width, height: $0.height) }.prefix(slotCount))
    }

    /// `sizes` padded with empty slots to `slotCount`.
    static func slots(_ sizes: [CustomSize]) -> [CustomSize?] {
        let filled = sanitized(sizes)
        return filled.map { $0 } + Array(repeating: nil, count: slotCount - filled.count)
    }

    /// Fills the first empty slot with `size`; unchanged when it is invalid or every slot is filled.
    static func adding(_ size: CustomSize, to sizes: [CustomSize]) -> [CustomSize] {
        let filled = sanitized(sizes)
        guard filled.count < slotCount, isValid(width: size.width, height: size.height) else { return filled }
        return filled + [size]
    }

    /// Slot `index` with `size`; unchanged when `size` is invalid or the slot is empty.
    static func replacing(at index: Int, with size: CustomSize, in sizes: [CustomSize]) -> [CustomSize] {
        var filled = sanitized(sizes)
        guard filled.indices.contains(index), isValid(width: size.width, height: size.height) else { return filled }
        filled[index] = size
        return filled
    }

    /// Without slot `index`: the ones below move up, and the empty slot is at the bottom.
    static func removing(at index: Int, from sizes: [CustomSize]) -> [CustomSize] {
        var filled = sanitized(sizes)
        guard filled.indices.contains(index) else { return filled }
        filled.remove(at: index)
        return filled
    }

    /// Slot `source` moved to `destination`, counted as `Array.move(fromOffsets:toOffset:)` does:
    /// the gap before which it goes. A filled slot never moves below the filled ones.
    static func moving(from source: Int, to destination: Int, in sizes: [CustomSize]) -> [CustomSize] {
        let filled = sanitized(sizes)
        return moved(filled, from: source, to: destination, within: filled.count)
    }

    /// `items` with `source` moved to the gap `destination`, both within the first `count` items;
    /// unchanged when `source` isn't among them. The Custom Sizes window moves its rows' identities
    /// the same way as their sizes.
    static func moved<T>(_ items: [T], from source: Int, to destination: Int, within count: Int) -> [T] {
        guard (0..<min(count, items.count)).contains(source) else { return items }
        var items = items
        let item = items.remove(at: source)
        let gap = min(max(destination, 0), count)
        items.insert(item, at: gap > source ? gap - 1 : gap)
        return items
    }
}

extension KeyedDecodingContainer {
    /// Saved custom sizes: each element on its own, missing or unreadable ones dropped, then
    /// `StudioSizes.sanitized`. A missing key or a value of another type is no sizes.
    func customSizes(_ key: Key) -> [CustomSize] {
        StudioSizes.sanitized(value(key, or: [Lenient<CustomSize>]()).compactMap(\.value))
    }
}

/// How a drag of a handle resizes the studio's frame or the Capture Area.
enum ResizeRule: Equatable, Sendable {
    case free
    /// Shift on a corner: square.
    case square
    /// Aspect Lock: this width-to-height ratio.
    case aspect(CGFloat)

    /// Shift on a corner squares, whether Aspect Lock is on or not; otherwise the lock's ratio, if
    /// there is one; otherwise free. Shift on a side does nothing of its own.
    static func forDrag(of handle: OverlayHandle, shift: Bool, aspectRatio: CGFloat?) -> ResizeRule {
        let isCorner = (handle.movesMinX || handle.movesMaxX) && (handle.movesMinY || handle.movesMaxY)
        if isCorner && shift { return .square }
        return aspectRatio.map { .aspect($0) } ?? .free
    }
}

/// Aspect Lock (docs/product.md, Screenshot studio): resizing the studio's frame by a handle keeps
/// a width-to-height ratio.
enum AspectLock {
    /// Which side of a corner drag sets the size.
    enum Lead: Equatable, Sendable {
        /// The longer side, measured in the ratio: the frame follows the pointer.
        case longer
        case width
        case height
    }

    /// The side ⌘-snapping moved, comparing the rect of a corner drag before (`resized`) and after
    /// (`snapped`) it: that side leads, so the snap holds. `.longer` when it moved neither side, or
    /// both.
    static func lead(resized: CGRect, snapped: CGRect) -> Lead {
        let width = resized.width != snapped.width
        let height = resized.height != snapped.height
        if width && !height { return .width }
        if height && !width { return .height }
        return .longer
    }

    /// `rect`, as a drag of `handle` resized it, made `ratio` (width / height) on the pixel grid of
    /// `scale`, keeping `minimumSize` points. A corner keeps the opposite corner in place and `lead`
    /// decides the size. A side keeps its own length and the opposite side in place; the other sides
    /// change around their middle.
    static func resized(
        _ rect: CGRect, handle: OverlayHandle, ratio: CGFloat, scale: CGFloat, minimumSize: CGSize,
        lead: Lead = .longer
    )
        -> CGRect
    {
        let movesX = handle.movesMinX || handle.movesMaxX
        let movesY = handle.movesMinY || handle.movesMaxY
        let minWidth = (max(minimumSize.width, minimumSize.height * ratio) * scale).rounded(.up)
        var width: CGFloat
        if movesX && movesY {
            switch lead {
            case .longer: width = max(rect.width, rect.height * ratio) * scale
            case .width: width = rect.width * scale
            case .height: width = rect.height * ratio * scale
            }
        } else if movesX {
            width = rect.width * scale
        } else {
            width = rect.height * ratio * scale
        }
        width = max(width.rounded(), minWidth)
        let height = max((width / ratio).rounded(), 1)
        // Back to points: whole pixels of `scale`.
        let size = CGSize(width: width / scale, height: height / scale)
        func onGrid(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }

        let x: CGFloat
        if handle.movesMinX {
            x = rect.maxX - size.width
        } else if handle.movesMaxX {
            x = rect.minX
        } else {
            x = onGrid(rect.midX - size.width / 2)
        }
        let y: CGFloat
        if handle.movesMinY {
            y = rect.maxY - size.height
        } else if handle.movesMaxY {
            y = rect.minY
        } else {
            y = onGrid(rect.midY - size.height / 2)
        }
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
