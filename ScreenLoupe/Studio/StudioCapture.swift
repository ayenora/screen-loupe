import AppKit
import OSLog
@preconcurrency import ScreenCaptureKit

/// One screenshot of the Screenshot studio's frame with `SCScreenshotManager`, as ⇧⌘3 takes the
/// screen: windows with their shadows and outlines, which a capture with a content filter leaves
/// out, and without the pointer. It leaves out every window of the app — the studio's frame, palette
/// and hover label, alerts, panels — except the ones the caller names: the Viewer, the Capture Area
/// frame and the studio's backdrop, which are captured like any other window on screen. So the
/// picture is what the frame shows, the backdrop's background among it. Or, for One Window, takes
/// one window alone, on transparency.
@MainActor
enum StudioCapture {
    /// How long a ScreenCaptureKit call may take, as for the stream.
    private static let callTimeout: Double = 5

    struct PictureSizeError: LocalizedError {
        var errorDescription: String?
    }

    /// The pixels `request` cuts out (`DisplayCoordinateConverter.screenshotRequest`), at `display`'s
    /// native resolution, in its colour space. `includedWindows` are window numbers of this app's
    /// windows to keep.
    ///
    /// `captureImage(in:)` has no filter: it takes every window on screen in the rect. So this app's
    /// other windows are hidden from screen capture (`sharingType` `.none`, which the call already
    /// honours) while it runs, and put back as they were right after, whatever happens: they stay
    /// visible to screen sharing. An open menu is a window of `NSApp.windows` too
    /// (`NSPopupMenuWindow`, at the pop-up menu level, measured on macOS 27): `keepsMenus`, a
    /// picture taken by the timer, keeps it (`StudioFilter.hides`). A window shown while the call
    /// runs isn't hidden.
    static func image(
        _ request: ScreenshotRequest, on display: DisplayInfo, including includedWindows: [Int], keepsMenus: Bool
    ) async throws -> CGImage {
        let kept = Set(includedWindows)
        let hidden = NSApp.windows.filter {
            StudioFilter.hides(
                number: $0.windowNumber, isShared: $0.sharingType != .none, kept: kept,
                isMenu: $0.level >= .popUpMenu, keepsMenus: keepsMenus)
        }
        let sharing = hidden.map(\.sharingType)
        for window in hidden { window.sharingType = .none }
        defer { for (window, type) in zip(hidden, sharing) { window.sharingType = type } }
        let rect = request.rect.rect
        let image = try await withTimeout(seconds: callTimeout) {
            try await SCScreenshotManager.captureImage(in: rect)
        }
        // Whole points come at their size exactly; anything else would put the crop off.
        guard image.width == request.pictureSize.width, image.height == request.pictureSize.height,
            let cut = image.cropping(
                to: CGRect(x: request.crop.x, y: request.crop.y, width: request.crop.width, height: request.crop.height)
            )
        else {
            // `StudioController` logs it, as every failure.
            throw PictureSizeError(
                errorDescription: """
                    The capture of \(rect) pt on a \(display.scale)× display came \(image.width) × \(image.height) px, \
                    not \(request.pictureSize.width) × \(request.pictureSize.height) px.
                    """)
        }
        return await converted(cut, to: NSScreen.colorSpace(forDisplay: display.id)) ?? cut
    }

    /// One picture of `size` pixels at the display's native resolution, in BGRA, never scaled to fit.
    private static func configuration(size: PixelSize) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = size.width
        configuration.height = size.height
        configuration.captureResolution = .best
        configuration.scalesToFit = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        return configuration
    }

    /// `StudioComposite.converted`, off the main actor: converting a large picture takes a while.
    @concurrent
    private nonisolated static func converted(_ image: CGImage, to space: CGColorSpace) async -> CGImage? {
        StudioComposite.converted(image, to: space)
    }

    struct WindowCaptureError: LocalizedError {
        var errorDescription: String?
    }

    /// One Window's picture: the window numbered `id` alone with `SCContentFilter(desktopIndependentWindow:)`,
    /// with or without its `shadow`, cut to its visible pixels at its native resolution
    /// (`OneWindowPicture.visibleBounds`), on transparency, in `display`'s colour space. `display`
    /// holds most of the window. Never scaled: a window not on screen, or of another scale than
    /// `display`'s, gives a `OneWindowProblem` before anything is captured.
    static func window(_ id: CGWindowID, display: DisplayInfo, shadow: Bool) async throws -> CGImage {
        let content = try await withTimeout(seconds: callTimeout) {
            try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        }
        let window = content.windows.first { $0.windowID == id }
        let filter = window.map { SCContentFilter(desktopIndependentWindow: $0) }
        if case .unavailable(let problem) = OneWindowPicture.shot(
            windowScale: filter.map { CGFloat($0.pointPixelScale) }, displayScale: display.scale)
        {
            throw problem
        }
        // Listed, as `shot` said.
        guard let window, let filter else { throw OneWindowProblem.notListed }
        let windowPixels = PixelSize(
            width: Int((window.frame.width * display.scale).rounded()),
            height: Int((window.frame.height * display.scale).rounded()))
        // Room to spare around the window for its shadow: ScreenCaptureKit scales a window down to
        // fit the output but never up, so the window with its shadow comes at its own size.
        let output = OneWindowPicture.captureSize(window: windowPixels, scale: display.scale)
        let configuration = Self.configuration(size: output)
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
            ofWindow: image, scale: display.scale, space: NSScreen.colorSpace(forDisplay: display.id))
    }

    /// A lone window's capture, taken at `scale`, cut to its visible pixels and put into `space`
    /// with its alpha, off the main actor: reading every pixel's alpha takes a while for a large
    /// window.
    @concurrent
    private nonisolated static func picture(
        ofWindow image: CGImage, scale: CGFloat, space: CGColorSpace
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
        guard
            let cut = image.cropping(
                to: CGRect(x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height)),
            let picture = StudioComposite.converted(cut, to: space, keepingAlpha: true)
        else { throw WindowCaptureError(errorDescription: "The window's picture couldn't be made.") }
        return picture
    }

    private static let log = Logger(category: "studio")
}
