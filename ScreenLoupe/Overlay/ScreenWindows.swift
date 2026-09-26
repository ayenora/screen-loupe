import AppKit

/// The windows of other apps on screen, for snapping the Capture Area, picking a window and the magnet.
@MainActor
enum ScreenWindows {
    /// The ordinary windows of other apps on screen, front to back. Menus, the Dock, the menu bar and
    /// this app's own windows are left out.
    static func windows(converter: DisplayCoordinateConverter) -> [ScreenWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return list.compactMap { info in
            guard (info[kCGWindowOwnerPID as String] as? pid_t) != ownPID,
                let window = window(info, converter: converter),
                window.layer == 0, window.alpha > 0, !window.frame.isEmpty
            else { return nil }
            return window
        }
    }

    /// Frames of `windows(converter:)`, in AppKit global coordinates.
    static func frames(converter: DisplayCoordinateConverter) -> [CGRect] {
        windows(converter: converter).map(\.frame)
    }

    /// The window numbered `id` as the list reports it now, or `nil` once it is closed. Minimised,
    /// hidden with its app or on another Space, it comes back empty too, as measured on macOS 27, or
    /// marked off screen; `WindowMagnet.holds` treats both the same. Reads that one window only, so
    /// it costs about 0.1 ms.
    static func window(_ id: CGWindowID, converter: DisplayCoordinateConverter) -> ScreenWindow? {
        guard let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]] else { return nil }
        return list.first.flatMap { window($0, converter: converter) }
    }

    private static func window(_ info: [String: Any], converter: DisplayCoordinateConverter) -> ScreenWindow? {
        guard let id = info[kCGWindowNumber as String] as? CGWindowID,
            let layer = info[kCGWindowLayer as String] as? Int,
            let bounds = info[kCGWindowBounds as String] as? NSDictionary,
            let quartz = CGRect(dictionaryRepresentation: bounds)
        else { return nil }
        return ScreenWindow(
            id: id, frame: converter.globalRect(QuartzRect(rect: quartz)).rect, layer: layer,
            isOnScreen: info[kCGWindowIsOnscreen as String] as? Bool ?? false,
            alpha: info[kCGWindowAlpha as String] as? Double ?? 1)
    }
}
