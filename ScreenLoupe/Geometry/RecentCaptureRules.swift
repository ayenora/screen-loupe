import CoreGraphics
import Foundation

/// What Recent Captures keeps and how its rows read.
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

    /// Where the snapshot of `area` sat in the Capture Area when it was taken: the kept picture's
    /// top-left, in whole pixels as `FrameLayout.cropped(toArea:)` cuts it. Kept with the capture, so
    /// used as a reference it lands on the pixels it was taken from (`CaptureReference`).
    static func snapshotOrigin(area: CGRect) -> CGPoint {
        area.integral.origin
    }

    /// A capture's place in the Capture Area (`ViewerFrame.areaOrigin`) after the area's top-left
    /// moved by `shift` pixels (its left or top edge dragged): a snapshot stays on the screen pixels
    /// it was taken from, as the reference layers do (`ReferenceStack.followAreaOrigin`), so the
    /// two keep lining up, and with a later snapshot of the same pixels. An image has no place in
    /// the area and stays at its corner.
    static func areaOrigin(_ origin: CGPoint, isFile: Bool, followingShift shift: CGPoint) -> CGPoint {
        isFile ? origin : CGPoint(x: origin.x - shift.x, y: origin.y - shift.y)
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

    /// `items`, newest first, with `item`, a capture kept from the last session that was read after
    /// the list came up, where it belongs: below every capture added since, which are newer, and
    /// among the other kept ones as `order` (the kept ones' ids, newest first) has them.
    static func restoring<Item, ID: Equatable>(
        _ item: Item, into items: [Item], order: [ID], id: (Item) -> ID
    ) -> [Item] {
        let rank = order.firstIndex(of: id(item)) ?? order.count
        let index =
            items.firstIndex { other in order.firstIndex(of: id(other)).map { $0 > rank } ?? false } ?? items.count
        var next = items
        next.insert(item, at: index)
        return next
    }

    /// How a capture shows: its zoom and offset. `nil` zoom: fitted to the Viewer, as an image file
    /// first shows.
    struct CaptureView: Equatable {
        var zoom: CGFloat?
        var offset: CGPoint
    }

    /// A recent capture as linking sees it. Linked captures share one zoom and offset, not the
    /// selection, so any of them shown opens at the same spot.
    struct Link<ID: Equatable>: Equatable {
        let id: ID
        /// The kept picture's size: only pictures of one size can be linked.
        let size: PixelSize
        var isLinked: Bool
        var view: CaptureView
    }

    /// What linking a capture does: every capture as it is after, and whether the Viewer moves to
    /// the linked capture's new view, as it is the one shown.
    struct Linking<ID: Equatable>: Equatable {
        var links: [Link<ID>]
        var showsNewView: Bool
    }

    /// A linked capture kept from the last session, read after the list came up, as it joins `links`:
    /// it takes the view the linked ones keep, which may have moved since; when they are of another
    /// size — linked since — it is unlinked, as only pictures of one size can be linked.
    static func joining<ID>(_ link: Link<ID>, into links: [Link<ID>]) -> Link<ID> {
        guard link.isLinked, let group = links.first(where: \.isLinked) else { return link }
        var next = link
        if group.size == link.size { next.view = group.view } else { next.isLinked = false }
        return next
    }

    /// Whether capture `id` can be linked now, or unlinked: linked captures share one zoom and
    /// offset, which only land on the same pixels in pictures of the same size. The first can be
    /// linked whatever its size, and any again once none is linked.
    static func canLink<ID>(_ id: ID, in links: [Link<ID>]) -> Bool {
        guard let link = links.first(where: { $0.id == id }) else { return false }
        return link.isLinked || links.allSatisfy { !$0.isLinked || $0.size == link.size }
    }

    /// The captures after capture `id` is put away at `view`: it keeps the view, and when it is
    /// linked so does every linked one, so any of them shown later opens where it was left.
    static func leaving<ID>(_ id: ID, at view: CaptureView, in links: [Link<ID>]) -> [Link<ID>] {
        let isLinked = links.first { $0.id == id }?.isLinked == true
        return links.map { link in
            var link = link
            if link.id == id || (isLinked && link.isLinked) { link.view = view }
            return link
        }
    }

    /// Links capture `id`, with `shown` in the Viewer at `viewer`. It takes the group's view: the
    /// Viewer's while a linked capture shows, as that may have moved since the group's was kept; else
    /// the one the linked captures keep. The first keeps its own. When it is the one shown and the
    /// group's view isn't the Viewer's, the Viewer moves to it: its kept view may be older than what
    /// shows. `nil` when it can't be linked or already is.
    static func linking<ID>(_ id: ID, shown: ID?, viewer: CaptureView, in links: [Link<ID>]) -> Linking<ID>? {
        guard let index = links.firstIndex(where: { $0.id == id }), !links[index].isLinked,
            canLink(id, in: links)
        else { return nil }
        let shownIsLinked = links.contains { $0.id == shown && $0.isLinked }
        let group = shownIsLinked ? viewer : links.first { $0.isLinked }?.view
        var next = links
        next[index].isLinked = true
        if let group { next[index].view = group }
        return Linking(links: next, showsNewView: id == shown && group != nil && group != viewer)
    }

    /// Unlinks capture `id`, with `shown` in the Viewer at `viewer`. It keeps its view as its own.
    /// When it is the one shown, the Viewer's view goes to the whole group first, so the group holds
    /// what was last on screen.
    static func unlinking<ID>(_ id: ID, shown: ID?, viewer: CaptureView, in links: [Link<ID>]) -> [Link<ID>] {
        guard let link = links.first(where: { $0.id == id }), link.isLinked else { return links }
        var next = id == shown ? leaving(id, at: viewer, in: links) : links
        if let index = next.firstIndex(where: { $0.id == id }) { next[index].isLinked = false }
        return next
    }

    /// A row's size: "294 × 239 px", the kept picture's own pixels.
    static func sizeText(_ size: PixelSize) -> String {
        "\(size.width) × \(size.height) px"
    }

    /// Writes a row's date and time: month and day as `locale` writes them, then the 24-hour time
    /// with seconds — "7/12, 14:32:05" in the US, "12/07, 14:32:05" in the UK. Made once and reused,
    /// as a formatter is costly to make.
    static func dateFormatter(locale: Locale, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("MdHHmmss")
        return formatter
    }
}
