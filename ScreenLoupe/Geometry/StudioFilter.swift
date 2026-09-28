import CoreGraphics

/// A window as ScreenCaptureKit lists it (`SCWindow`), for choosing what a studio picture leaves out.
struct ListedWindow: Equatable, Sendable {
    var id: CGWindowID
    /// The owning process, or `nil` for a window without one.
    var ownerPID: Int32?
}

/// Which windows a studio picture leaves out: every window of this app but the kept ones — the
/// Viewer, the Capture Area frame and the studio's backdrop. Nothing of other apps or of the
/// system: the backdrop covers the wallpaper and the desktop icons on screen, so the picture is
/// what the frame shows. The Viewer's stream leaves out its windows the same way, keeping only the
/// studio's backdrop.
enum StudioFilter {
    /// How the filter is made (`StudioFilter.path`).
    enum Path: Equatable, Sendable {
        /// The app excluded as a whole, its kept windows excepted.
        case excludingApp
        /// These windows named one by one (`excluded`).
        case excludingWindows([CGWindowID])
    }

    /// Excludes the app as a whole when it is listed, which also covers a window of the app that
    /// appears while the picture is taken; otherwise (docs/design.md §6, risk 4) names every window
    /// to leave out.
    static func path(_ windows: [ListedWindow], ownPID: Int32, appIsListed: Bool, kept: Set<CGWindowID>) -> Path {
        appIsListed ? .excludingApp : .excludingWindows(excluded(windows, ownPID: ownPID, kept: kept))
    }

    /// Every window a picture leaves out when the filter names them one by one: this app's windows
    /// except `kept`, in list order.
    static func excluded(_ windows: [ListedWindow], ownPID: Int32, kept: Set<CGWindowID>) -> [CGWindowID] {
        windows.filter { $0.ownerPID == ownPID && !kept.contains($0.id) }.map(\.id)
    }
}
