import CoreGraphics

/// A window as ScreenCaptureKit lists it (`SCWindow`), for choosing what a studio picture leaves out.
struct ListedWindow: Equatable, Sendable {
    var id: CGWindowID
    /// The window's level: 0 for an ordinary window.
    var layer: Int
    /// The owning process, or `nil` for a window without one.
    var ownerPID: Int32?
    var ownerBundleID: String?
}

/// Which listed windows a studio picture leaves out besides the app's own: with a background other
/// than the screen (`StudioBackground.leavesOutWallpaper`), the desktop — the wallpaper and the
/// desktop icons — so the background shows where they were.
///
/// How the system draws the desktop, as the window list shows it on macOS 27: the wallpaper is a
/// window of WallpaperAgent two levels below `kCGDesktopWindowLevel`, with a window of Stage
/// Manager's WindowManager and some of the window server's own at the levels around it. The desktop
/// icons are Finder's window at `kCGDesktopIconWindowLevel`. So the wallpaper goes by level alone,
/// whichever process draws it, and the icons by owner and level together, which keeps Finder's
/// ordinary windows.
enum StudioFilter {
    static let desktopIconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
    static let finderBundleID = "com.apple.finder"

    /// Everything below the desktop icons: the wallpaper, whichever process draws it.
    static func isWallpaper(_ window: ListedWindow) -> Bool {
        window.layer < desktopIconLevel
    }

    static func isDesktopIcons(_ window: ListedWindow) -> Bool {
        window.ownerBundleID == finderBundleID && window.layer == desktopIconLevel
    }

    /// The windows of other apps and of the system a picture leaves out, in list order: the
    /// wallpaper and the desktop icons when `leavingOutDesktop`, else none. This app's own windows
    /// are never among them: whether they show is decided apart (`excluded`).
    static func othersLeftOut(_ windows: [ListedWindow], ownPID: Int32, leavingOutDesktop: Bool) -> [CGWindowID] {
        guard leavingOutDesktop else { return [] }
        return windows.filter { window in
            window.ownerPID != ownPID && (isWallpaper(window) || isDesktopIcons(window))
        }
        .map(\.id)
    }

    /// How the filter is made (`StudioFilter.path`).
    enum Path: Equatable, Sendable {
        /// The app excluded as a whole, its kept windows excepted: nothing of other apps is left out.
        case excludingApp
        /// These windows named one by one (`excluded`).
        case excludingWindows([CGWindowID])
    }

    /// Excludes the app as a whole when it is listed and nothing of other apps is left out, which
    /// also covers a window of the app that appears while the picture is taken; otherwise names
    /// every window to leave out, since `excludingApplications` takes no windows of other apps.
    static func path(
        _ windows: [ListedWindow], ownPID: Int32, appIsListed: Bool, kept: Set<CGWindowID>, leavingOutDesktop: Bool
    ) -> Path {
        if appIsListed, othersLeftOut(windows, ownPID: ownPID, leavingOutDesktop: leavingOutDesktop).isEmpty {
            return .excludingApp
        }
        return .excludingWindows(excluded(windows, ownPID: ownPID, kept: kept, leavingOutDesktop: leavingOutDesktop))
    }

    /// Every window a picture leaves out when the filter names them one by one: this app's windows
    /// except `kept` (the Viewer and the Capture Area frame), then `othersLeftOut`.
    static func excluded(
        _ windows: [ListedWindow], ownPID: Int32, kept: Set<CGWindowID>, leavingOutDesktop: Bool
    ) -> [CGWindowID] {
        let own = windows.filter { $0.ownerPID == ownPID && !kept.contains($0.id) }.map(\.id)
        return own + othersLeftOut(windows, ownPID: ownPID, leavingOutDesktop: leavingOutDesktop)
    }
}
