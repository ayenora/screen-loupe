import AppKit
import OSLog
@preconcurrency import ScreenCaptureKit

/// One screenshot of the Screenshot studio's frame with `SCScreenshotManager` (docs/design.md,
/// Screenshot studio). Like the Viewer's stream it leaves out every window of the app — the studio's
/// frame, palette and hover label, menus, alerts — except the ones the caller names: the Viewer and
/// the Capture Area frame, which are captured like any other window on screen. It also leaves out
/// the Dock, the desktop icons, the wallpaper and chosen windows of other apps, as asked, and lays
/// a background under what is left. Or, for One Window, takes one window alone.
@MainActor
enum StudioCapture {
    struct NoDisplayError: LocalizedError {
        var errorDescription: String? { "The display isn't available for capture." }
    }

    /// How long a ScreenCaptureKit call may take, as for the stream (docs/design.md §2.1).
    private static let callTimeout: Double = 5

    /// The pixels of `geometry` at the display's native resolution, with the pointer when `pointer`
    /// says so, in the display's colour space. `includedWindows` are window numbers of this app's
    /// windows to keep; `leaveOut` names what else stays out of the picture, and `fill` is laid
    /// under what is left.
    static func image(
        of geometry: CaptureGeometry, including includedWindows: [Int], leavingOut leaveOut: StudioLeaveOut,
        pointer: Bool, over fill: StudioFill?
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
        configuration.showsCursor = pointer
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
        return await composited(image, in: NSScreen.colorSpace(forDisplay: display.displayID), over: fill) ?? image
    }

    /// `StudioComposite.composited`, off the main actor: a large picture over an image takes a while
    /// to draw.
    @concurrent
    private nonisolated static func composited(
        _ image: CGImage, in space: CGColorSpace, over fill: StudioFill?
    ) async -> CGImage? {
        StudioComposite.composited(image, in: space, over: fill)
    }

    /// Why One Window captured nothing; each is said beside the tab.
    enum WindowProblem: Error {
        /// Not among the on-screen windows: closed, minimised, hidden or on another Space.
        case notListed
        /// Its pixels aren't the frame display's: it would have to be scaled.
        case otherScale
        /// The window itself is larger than the frame; its shadow never is too large.
        case largerThanFrame
    }

    struct WindowCaptureError: LocalizedError {
        var errorDescription: String?
    }

    /// One Window's picture: the window numbered `id` alone with `SCContentFilter(desktopIndependentWindow:)`,
    /// with or without its `shadow`, at its native pixels, centred in a picture of `frame` pixels,
    /// grown where the window with its shadow needs more (`OneWindowPicture.pictureSize`), in
    /// `display`'s colour space, over `fill` or transparent without one (docs/design.md, Screenshot
    /// studio). Never scaled: a window on a display of another scale, or itself larger than the
    /// frame, gives a `WindowProblem`.
    static func window(
        _ id: CGWindowID, frame: PixelSize, display: DisplayInfo, shadow: Bool, over fill: StudioFill?
    ) async throws -> CGImage {
        let content = try await withTimeout(seconds: callTimeout) {
            try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        }
        guard let window = content.windows.first(where: { $0.windowID == id }) else { throw WindowProblem.notListed }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        guard CGFloat(filter.pointPixelScale) == display.scale else { throw WindowProblem.otherScale }
        // The window alone must fit the frame; its shadow may grow the picture.
        let windowPixels = PixelSize(
            width: Int((window.frame.width * display.scale).rounded()),
            height: Int((window.frame.height * display.scale).rounded()))
        guard OneWindowPicture.fits(windowPixels, in: frame) else { throw WindowProblem.largerThanFrame }
        // Room to spare around the window for its shadow: ScreenCaptureKit scales a window down to
        // fit the output but never up, so the window with its shadow comes at its own size.
        let output = OneWindowPicture.captureSize(window: windowPixels, scale: display.scale)
        let configuration = SCStreamConfiguration()
        configuration.width = output.width
        configuration.height = output.height
        configuration.captureResolution = .best
        configuration.scalesToFit = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        // The pointer isn't a part of the window: One Window leaves it out.
        configuration.showsCursor = false
        configuration.backgroundColor = CGColor.clear
        configuration.ignoreShadowsSingleWindow = !shadow
        // A window partly off the screen comes whole.
        configuration.ignoreGlobalClipSingleWindow = true
        let image = try await withTimeout(seconds: callTimeout) {
            try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        }
        log.debug(
            """
            One window: content \(String(describing: filter.contentRect), privacy: .public) pt at \
            \(filter.pointPixelScale)×, window \(String(describing: window.frame), privacy: .public) pt, \
            image \(image.width) × \(image.height) px in \(String(describing: image.colorSpace?.name), privacy: .public)
            """)
        return try await picture(
            ofWindow: image, frame: frame, scale: display.scale, space: NSScreen.colorSpace(forDisplay: display.id),
            over: fill)
    }

    /// A lone window's capture, taken at `scale`, cut to its visible pixels and centred in a picture
    /// of `frame` pixels grown to hold them, off the main actor: reading every pixel's alpha and
    /// drawing take a while for a large frame.
    @concurrent
    private nonisolated static func picture(
        ofWindow image: CGImage, frame: PixelSize, scale: CGFloat, space: CGColorSpace, over fill: StudioFill?
    ) async throws -> CGImage {
        // Where the window and its shadow are is told by alpha alone.
        guard StudioComposite.hasAlpha(image) else {
            throw WindowCaptureError(errorDescription: "The window's capture has no alpha.")
        }
        guard let bounds = OneWindowPicture.visibleBounds(of: image) else {
            throw WindowCaptureError(errorDescription: "The window's capture is empty.")
        }
        // A shadow larger than the room would have the whole capture scaled down: not a picture.
        guard
            !OneWindowPicture.isScaledDown(
                visible: bounds.size, capture: PixelSize(width: image.width, height: image.height), scale: scale)
        else {
            throw WindowCaptureError(
                errorDescription: "The window's capture \(image.width) × \(image.height) px came scaled down.")
        }
        let size = OneWindowPicture.pictureSize(frame: frame, visible: bounds.size)
        guard
            let cut = image.cropping(
                to: CGRect(x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height)),
            let picture = StudioComposite.centred(cut, in: size, space: space, over: fill)
        else { throw WindowCaptureError(errorDescription: "The window's picture couldn't be made.") }
        return picture
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
