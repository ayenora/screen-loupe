import AppKit

/// The windows of other apps on screen, for snapping the Capture Area and picking a window.
@MainActor
enum ScreenWindows {
    /// Frames of the ordinary windows of other apps on screen, front to back, in AppKit global
    /// coordinates. Menus, the Dock, the menu bar and this app's own windows are left out.
    static func frames(converter: DisplayCoordinateConverter) -> [CGRect] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                (info[kCGWindowOwnerPID as String] as? pid_t) != ownPID,
                (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                let quartz = CGRect(dictionaryRepresentation: bounds),
                quartz.width > 0, quartz.height > 0
            else { return nil }
            return converter.globalRect(QuartzRect(rect: quartz)).rect
        }
    }
}
