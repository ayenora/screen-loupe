import AppKit
@preconcurrency import ScreenCaptureKit

/// One screenshot of the Screenshot studio's frame with `SCScreenshotManager` (docs/design.md,
/// Screenshot studio). Like the Viewer's stream it leaves out every window of the app — the studio's
/// frame, palette and hover label, menus, alerts — except the ones the caller names: the Viewer and
/// the Capture Area frame, which are captured like any other window on screen.
@MainActor
enum StudioCapture {
    struct NoDisplayError: LocalizedError {
        var errorDescription: String? { "The display isn't available for capture." }
    }

    /// How long a ScreenCaptureKit call may take, as for the stream (docs/design.md §2.1).
    private static let callTimeout: Double = 5

    /// The pixels of `geometry` at the display's native resolution, without the pointer, in the
    /// display's colour space. `includedWindows` are window numbers of this app's windows to keep.
    static func image(of geometry: CaptureGeometry, including includedWindows: [Int]) async throws -> CGImage {
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
        let filter = filter(for: display, in: content, including: Set(includedWindows.map { CGWindowID($0) }))
        let image = try await withTimeout(seconds: callTimeout) {
            try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        }
        return inDisplaySpace(image, NSScreen.colorSpace(forDisplay: display.displayID))
    }

    /// The display minus every window of this app but `included`; the stream's fallback when the app
    /// isn't listed (docs/design.md §6, risk 4).
    private static func filter(
        for display: SCDisplay, in content: SCShareableContent, including included: Set<CGWindowID>
    ) -> SCContentFilter {
        let pid = ProcessInfo.processInfo.processIdentifier
        let kept = content.windows.filter { included.contains($0.windowID) }
        if let app = content.applications.first(where: { $0.processID == pid }) {
            return SCContentFilter(display: display, excludingApplications: [app], exceptingWindows: kept)
        }
        let ours = content.windows.filter {
            $0.owningApplication?.processID == pid && !included.contains($0.windowID)
        }
        return SCContentFilter(display: display, excludingWindows: ours)
    }

    /// The capture comes in the display's colour space unless configured otherwise (the header of
    /// `SCStreamConfiguration.colorSpaceName`), as the stream's frames do. An image tagged with that
    /// space is kept as it is, an untagged one is tagged with it, and one in any other space is
    /// converted into it, so the pixels and the saved profile always agree.
    private static func inDisplaySpace(_ image: CGImage, _ space: CGColorSpace) -> CGImage {
        guard let own = image.colorSpace else { return image.copy(colorSpace: space) ?? image }
        if own == space { return image }
        guard
            let context = CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return image }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage() ?? image
    }
}
