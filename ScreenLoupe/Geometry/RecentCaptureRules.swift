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

    /// The source pixels a snapshot keeps, for the live view's `state`: the Select tool's `selection`
    /// when there is one, whether the viewport shows all of it or not; else every pixel the viewport
    /// shows, even in part. Only the part inside the image: zoomed out, the space around it isn't
    /// kept. `nil` when none of the image is.
    static func snapshotArea(selection: CGRect?, in state: ZoomPanState) -> CGRect? {
        if let selection, let inside = PixelSelection.clamped(selection, to: state.contentSize) { return inside }
        return ViewRegion.sourceRect(of: CGRect(origin: .zero, size: state.viewportSize), in: state)
    }

    /// Where the snapshot of `area` opens at the live view's `zoom`: the live `offset` moved by the
    /// area's corner, so the kept pixels show where the live view showed them.
    static func snapshotOffset(_ offset: CGPoint, zoom: CGFloat, area: CGRect) -> CGPoint {
        CGPoint(x: offset.x + area.minX * zoom, y: offset.y + area.minY * zoom)
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
