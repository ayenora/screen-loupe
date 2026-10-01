import CoreGraphics

/// A window as ScreenCaptureKit lists it (`SCWindow`), for choosing what the Viewer's stream leaves out.
struct ListedWindow: Equatable, Sendable {
    var id: CGWindowID
    /// The owning process, or `nil` for a window without one.
    var ownerPID: Int32?
}

/// Which windows a capture leaves out: every window of this app but the kept ones. Nothing of other
/// apps or of the system: the studio's backdrop covers the wallpaper and the desktop icons on
/// screen, so a picture is what the frame shows. The Viewer's stream keeps only the backdrop, with
/// a content filter; a studio picture keeps the Viewer, the Capture Area frame and the backdrop too,
/// and hides the others from screen capture while it is taken (`hides`).
enum StudioFilter {
    /// How the filter is made (`StudioFilter.path`).
    enum Path: Equatable, Sendable {
        /// The app excluded as a whole, its kept windows excepted.
        case excludingApp
        /// These windows named one by one (`excluded`).
        case excludingWindows([CGWindowID])
    }

    /// Excludes the app as a whole when it is listed, which also covers a window of the app that
    /// appears while the stream runs; otherwise names every window
    /// to leave out.
    static func path(_ windows: [ListedWindow], ownPID: Int32, appIsListed: Bool, kept: Set<CGWindowID>) -> Path {
        appIsListed ? .excludingApp : .excludingWindows(excluded(windows, ownPID: ownPID, kept: kept))
    }

    /// Every window a stream leaves out when the filter names them one by one: this app's windows
    /// except `kept`, in list order.
    static func excluded(_ windows: [ListedWindow], ownPID: Int32, kept: Set<CGWindowID>) -> [CGWindowID] {
        windows.filter { $0.ownerPID == ownPID && !kept.contains($0.id) }.map(\.id)
    }

    /// Whether a studio picture hides this app's window numbered `number` from screen capture while
    /// it is taken: every window but `kept` that screen capture sees now (`isShared`), so each one
    /// hidden goes back as it was. A number of zero or less is a window never shown, which keeps
    /// nothing: a kept window not shown yet doesn't keep every other such window. An open menu
    /// (`isMenu`, its window at the pop-up menu level) is kept with `keepsMenus`, a picture taken
    /// by the timer, whose wait is for opening a menu to show; a picture taken at once hides it, so
    /// the menu of the command still fading out stays out.
    static func hides(
        number: Int, isShared: Bool, kept: Set<Int>, isMenu: Bool = false, keepsMenus: Bool = false
    )
        -> Bool
    {
        isShared && !(number > 0 && kept.contains(number)) && !(isMenu && keepsMenus)
    }
}
