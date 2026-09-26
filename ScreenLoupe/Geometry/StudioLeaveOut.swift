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

/// What a Screenshot studio picture leaves out besides the app's own windows (docs/product.md,
/// Screenshot studio): nothing on screen is hidden, the capture's filter leaves these out.
struct StudioLeaveOut: Equatable, Sendable {
    var dock = false
    var desktopIcons = false
    var wallpaper = false
    /// Windows of other apps left out by pointing.
    var windows: Set<CGWindowID> = []

    /// A background other than the screen leaves out the wallpaper and the desktop icons with it.
    init(dock: Bool, desktopIcons: Bool, background: StudioBackground, windows: Set<CGWindowID>) {
        self.dock = dock
        wallpaper = background.leavesOutWallpaper
        self.desktopIcons = desktopIcons || wallpaper
        self.windows = windows
    }

    init() {}
}

/// Which listed windows a studio picture leaves out.
///
/// How the system draws the desktop, as the window list shows it on macOS 27: the wallpaper is a
/// window of WallpaperAgent two levels below `kCGDesktopWindowLevel`, with a window of Stage
/// Manager's WindowManager and some of the window server's own at the levels around it. The desktop
/// icons are Finder's window at `kCGDesktopIconWindowLevel`, the Dock the Dock's window at
/// `kCGDockWindowLevel`. So the wallpaper goes by level alone, whichever process draws it, and the
/// icons and the Dock by owner and level together, which keeps Finder's ordinary windows and the
/// Dock's windows at other levels, such as its menus.
enum StudioFilter {
    static let desktopIconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
    static let dockLevel = Int(CGWindowLevelForKey(.dockWindow))
    static let finderBundleID = "com.apple.finder"
    static let dockBundleID = "com.apple.dock"

    /// Everything below the desktop icons: the wallpaper, whichever process draws it.
    static func isWallpaper(_ window: ListedWindow) -> Bool {
        window.layer < desktopIconLevel
    }

    static func isDesktopIcons(_ window: ListedWindow) -> Bool {
        window.ownerBundleID == finderBundleID && window.layer == desktopIconLevel
    }

    static func isDock(_ window: ListedWindow) -> Bool {
        window.ownerBundleID == dockBundleID && window.layer == dockLevel
    }

    /// The windows of other apps and of the system that `leaveOut` leaves out, in list order. This
    /// app's own windows are never among them: whether they show is decided apart (`excluded`).
    static func othersLeftOut(_ windows: [ListedWindow], ownPID: Int32, _ leaveOut: StudioLeaveOut) -> [CGWindowID] {
        windows.filter { window in
            guard window.ownerPID != ownPID else { return false }
            return (leaveOut.wallpaper && isWallpaper(window))
                || (leaveOut.desktopIcons && isDesktopIcons(window))
                || (leaveOut.dock && isDock(window))
                || leaveOut.windows.contains(window.id)
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
        _ windows: [ListedWindow], ownPID: Int32, appIsListed: Bool, kept: Set<CGWindowID>, _ leaveOut: StudioLeaveOut
    ) -> Path {
        if appIsListed, othersLeftOut(windows, ownPID: ownPID, leaveOut).isEmpty { return .excludingApp }
        return .excludingWindows(excluded(windows, ownPID: ownPID, kept: kept, leaveOut))
    }

    /// Every window a picture leaves out when the filter names them one by one: this app's windows
    /// except `kept` (the Viewer and the Capture Area frame), then `othersLeftOut`.
    static func excluded(
        _ windows: [ListedWindow], ownPID: Int32, kept: Set<CGWindowID>, _ leaveOut: StudioLeaveOut
    ) -> [CGWindowID] {
        let own = windows.filter { $0.ownerPID == ownPID && !kept.contains($0.id) }.map(\.id)
        return own + othersLeftOut(windows, ownPID: ownPID, leaveOut)
    }
}

/// The windows left out by pointing (docs/product.md, Screenshot studio): kept for the session, and
/// shown dimmed inside the studio's frame until the capture.
enum LeftOutWindows {
    /// A click on a window leaves it out, or brings it back when it was left out.
    static func toggled(_ id: CGWindowID, in leftOut: Set<CGWindowID>) -> Set<CGWindowID> {
        leftOut.symmetricDifference([id])
    }

    /// Without the windows that no longer exist. One minimised, hidden or on another Space still
    /// exists and stays left out.
    static func keeping(_ leftOut: Set<CGWindowID>, existing: Set<CGWindowID>) -> Set<CGWindowID> {
        leftOut.intersection(existing)
    }

    /// Whether a window on screen belongs in the stack `dimmedRects` takes: other apps' visible
    /// windows below the Dock's level — ordinary and floating ones, not the Dock's, the menu bar's
    /// or other overlays as large as a display, mostly transparent — and of this app's windows only
    /// `ownInStack` ones (the Viewer, the palette), not its transparent frames and overlays.
    static func isInStack(layer: Int, alpha: Double, isEmpty: Bool, isOwn: Bool, ownInStack: Bool) -> Bool {
        guard !isEmpty, alpha > 0 else { return false }
        if isOwn { return ownInStack }
        return (0..<StudioFilter.dockLevel).contains(layer)
    }

    /// What of the left-out windows is missing from a picture of the studio's `frame`, in AppKit
    /// global points. `stack` lists the windows on screen front to back, the left-out ones among
    /// them: each left-out window's rect, clipped to the frame, less every window in front of it
    /// that stays in the picture — a left-out window in front hides nothing, since it is gone too.
    /// Each piece is widened to whole pixels of `scale` (the frame's display) and kept inside the
    /// frame. Windows off screen, wholly outside the frame or wholly covered give none.
    static func dimmedRects(
        _ leftOut: Set<CGWindowID>, stack: [ScreenWindow], frame: CGRect, scale: CGFloat
    ) -> [CGRect] {
        let onScreen = stack.filter(\.isOnScreen)
        var rects: [CGRect] = []
        for (index, window) in onScreen.enumerated() where leftOut.contains(window.id) {
            var pieces = [window.frame.intersection(frame)].filter(isArea)
            for front in onScreen[..<index] where !leftOut.contains(front.id) {
                pieces = pieces.flatMap { subtracting(front.frame, from: $0) }
            }
            rects += pieces.map { widened($0, scale: scale).intersection(frame) }.filter(isArea)
        }
        return rects
    }

    /// `rect` less `cut`: up to four pieces — the bands above and below `cut`, then the parts left
    /// and right of it between them.
    static func subtracting(_ cut: CGRect, from rect: CGRect) -> [CGRect] {
        let overlap = rect.intersection(cut)
        guard isArea(overlap) else { return [rect] }
        return [
            CGRect(x: rect.minX, y: overlap.maxY, width: rect.width, height: rect.maxY - overlap.maxY),
            CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: overlap.minY - rect.minY),
            CGRect(x: rect.minX, y: overlap.minY, width: overlap.minX - rect.minX, height: overlap.height),
            CGRect(x: overlap.maxX, y: overlap.minY, width: rect.maxX - overlap.maxX, height: overlap.height),
        ].filter(isArea)
    }

    private static func isArea(_ rect: CGRect) -> Bool {
        !rect.isNull && rect.width > 0 && rect.height > 0
    }

    /// Out to the next whole pixels of `scale`.
    private static func widened(_ rect: CGRect, scale: CGFloat) -> CGRect {
        let minX = (rect.minX * scale).rounded(.down) / scale
        let minY = (rect.minY * scale).rounded(.down) / scale
        let maxX = (rect.maxX * scale).rounded(.up) / scale
        let maxY = (rect.maxY * scale).rounded(.up) / scale
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
