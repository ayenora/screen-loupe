import CoreGraphics

/// What Recent Captures keeps and how its rows read (docs/product.md, Recent Captures).
enum RecentCaptureRules {
    /// How many rows the list keeps.
    static let limit = 8

    /// The frame Take Snapshot keeps: the one the live view shows for the Capture Area — the frozen
    /// frame, else the one held while the magnet moves the area, else the latest live frame. A recent
    /// capture or an opened image shown in its place is never taken: a snapshot is of the screen.
    /// `nil` without a frame: nothing to take.
    static func snapshotFrame<Frame>(frozen: Frame?, held: Frame?, live: Frame?) -> Frame? {
        frozen ?? held ?? live
    }

    /// How a snapshot shows when it is opened: as the live view was left when it was taken. While a
    /// row shows, the live view's zoom and pan are the ones put away for it (`savedLive`), not the
    /// row's own.
    static func snapshotView<View>(savedLive: View?, current: View) -> View {
        savedLive ?? current
    }

    /// `items`, newest first, with `item` on top; past `limit` the oldest goes. The shown one is never
    /// pushed out from under the Viewer: the oldest other one goes instead.
    static func adding<Item>(_ item: Item, to items: [Item], limit: Int = limit, isShown: (Item) -> Bool) -> [Item] {
        var next = [item] + items
        if next.count > limit {
            let index = next.lastIndex { !isShown($0) } ?? next.count - 1
            next.remove(at: index)
        }
        return next
    }

    /// A row's size: "294 × 239 px", the kept picture's own pixels.
    static func sizeText(_ size: PixelSize) -> String {
        "\(size.width) × \(size.height) px"
    }
}
