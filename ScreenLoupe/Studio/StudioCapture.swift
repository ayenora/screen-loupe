import AppKit
import OSLog
@preconcurrency import ScreenCaptureKit

/// One screenshot of the Screenshot studio's frame with `SCScreenshotManager` (docs/design.md,
/// Screenshot studio). Like the Viewer's stream it leaves out every window of the app — the studio's
/// frame, palette and hover label, menus, alerts — except the ones the caller names: the Viewer and
/// the Capture Area frame, which are captured like any other window on screen. It also leaves out
/// the Dock, the desktop icons, the wallpaper and chosen windows of other apps, as asked, and lays
/// a background under what is left.
@MainActor
enum StudioCapture {
    struct NoDisplayError: LocalizedError {
        var errorDescription: String? { "The display isn't available for capture." }
    }

    /// How long a ScreenCaptureKit call may take, as for the stream (docs/design.md §2.1).
    private static let callTimeout: Double = 5

    /// The pixels of `geometry` at the display's native resolution, without the pointer, in the
    /// display's colour space. `includedWindows` are window numbers of this app's windows to keep;
    /// `leaveOut` names what else stays out of the picture, and `fill` is laid under what is left.
    static func image(
        of geometry: CaptureGeometry, including includedWindows: [Int], leavingOut leaveOut: StudioLeaveOut,
        over fill: StudioFill?
    ) async throws -> CGImage {
        let content = try await withTimeout(seconds: callTimeout) {
            try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        }
        guard let display = content.displays.first(where: { $0.displayID == geometry.display.id }) else {
            throw NoDisplayError()
        }
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = geometry.sourceRect.rect
        configuration.width = geometry.outputSize.width
        configuration.height = geometry.outputSize.height
        configuration.captureResolution = .best
        configuration.scalesToFit = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        // Where no window is left, nothing: a fill shows through there.
        configuration.backgroundColor = CGColor.clear
        let filter = filter(
            for: display, in: content, including: Set(includedWindows.map { CGWindowID($0) }), leavingOut: leaveOut)
        let image = try await withTimeout(seconds: callTimeout) {
            try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        }
        // Without alpha a fill can't show through: the picture is kept as captured rather than
        // pretending there is a background under it.
        var fill = fill
        if fill != nil, !StudioComposite.hasAlpha(image) {
            if !hasLoggedMissingAlpha {
                hasLoggedMissingAlpha = true
                log.error("The capture has no alpha; the background isn't laid under it.")
            }
            fill = nil
        }
        return StudioComposite.composited(image, in: NSScreen.colorSpace(forDisplay: display.displayID), over: fill)
            ?? image
    }

    private static let log = Logger(category: "studio")
    private static var hasLoggedMissingAlpha = false

    /// The display minus every window of this app but `included`, and minus what `leaveOut` names
    /// (`StudioFilter`). With nothing else to leave out, the app is excluded as a whole; otherwise,
    /// or when the app isn't listed (docs/design.md §6, risk 4), the windows are named one by one.
    private static func filter(
        for display: SCDisplay, in content: SCShareableContent, including included: Set<CGWindowID>,
        leavingOut leaveOut: StudioLeaveOut
    ) -> SCContentFilter {
        let pid = ProcessInfo.processInfo.processIdentifier
        let listed = content.windows.map {
            ListedWindow(
                id: $0.windowID, layer: $0.windowLayer, ownerPID: $0.owningApplication?.processID,
                ownerBundleID: $0.owningApplication?.bundleIdentifier)
        }
        let app = content.applications.first { $0.processID == pid }
        let path = StudioFilter.path(listed, ownPID: pid, appIsListed: app != nil, kept: included, leaveOut)
        if case .excludingWindows(let ids) = path {
            let excluded = Set(ids)
            return SCContentFilter(
                display: display, excludingWindows: content.windows.filter { excluded.contains($0.windowID) })
        }
        // `.excludingApp` comes only with the app listed.
        let kept = content.windows.filter { included.contains($0.windowID) }
        return SCContentFilter(display: display, excludingApplications: app.map { [$0] } ?? [], exceptingWindows: kept)
    }
}
