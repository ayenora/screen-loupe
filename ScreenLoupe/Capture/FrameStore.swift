import CoreVideo
import Foundation

/// A picture the Viewer shows: a frame of the stream, frozen or not, a recent capture or an opened
/// image. Every tool reads it through `layout`; only what follows the live Capture Area needs
/// `geometry`.
struct ViewerFrame: @unchecked Sendable {
    /// IOSurface-backed BGRA buffer. Never written to after capture, so sharing it across threads is
    /// safe; that is why the struct is `@unchecked Sendable`.
    let pixelBuffer: CVPixelBuffer
    let layout: FrameLayout
    /// The display the pixels come from, for their colour space; sRGB without one.
    let displayID: CGDirectDisplayID?
    /// An opened image's own colour space, which its pixels are in; `nil` for a picture of the
    /// screen, whose colour space is its display's (`colorSpace`).
    let imageColorSpace: CGColorSpace?
    /// The geometry the stream captured it with: a live frame, or one frozen from it. A recent
    /// capture or an opened image is a picture of its own, whose pixels don't map onto the Capture
    /// Area, so it has none: the crosshair, the cursor, the part the Viewer shows and following the
    /// area's edges don't apply to it.
    let geometry: CaptureGeometry?

    /// Whether the buffer's alpha is the picture's own, straight (not premultiplied): an opened
    /// image's transparency. Frames of the screen are opaque, whatever their alpha bytes hold.
    var hasAlpha: Bool { imageColorSpace != nil }

    init(
        pixelBuffer: CVPixelBuffer, layout: FrameLayout, displayID: CGDirectDisplayID?,
        imageColorSpace: CGColorSpace? = nil
    ) {
        self.pixelBuffer = pixelBuffer
        self.layout = layout
        self.displayID = displayID
        self.imageColorSpace = imageColorSpace
        geometry = nil
    }

    /// A frame of the stream.
    init(pixelBuffer: CVPixelBuffer, geometry: CaptureGeometry) {
        self.pixelBuffer = pixelBuffer
        layout = geometry.layout
        displayID = geometry.display.id
        imageColorSpace = nil
        self.geometry = geometry
    }

    var pixelSize: PixelSize {
        PixelSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
    }

    /// The frame copied into a buffer of its own, cut to `area` (whole pixels of the picture: what a
    /// snapshot keeps) and to `ImageBudget`, to keep as a recent capture. The stream's buffers come
    /// from a small pool it reuses; holding on to them would starve it. IOSurface-backed and
    /// Metal-compatible, so it is drawn like a live frame.
    func copiedForKeeping(area: CGRect) -> ViewerFrame? {
        guard let cut = layout.cropped(toArea: area), let kept = cut.layout.fittedToImageBudget() else { return nil }
        let offset = cut.offset
        let width = kept.imageSize.width
        let height = kept.imageSize.height
        guard let copy = Self.makeBuffer(width: width, height: height) else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        CVPixelBufferLockBaseAddress(copy, [])
        defer {
            CVPixelBufferUnlockBaseAddress(copy, [])
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        }
        guard let from = CVPixelBufferGetBaseAddress(pixelBuffer), let to = CVPixelBufferGetBaseAddress(copy) else {
            return nil
        }
        let fromRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let toRow = CVPixelBufferGetBytesPerRow(copy)
        // The kept image starts at `offset` in the captured one.
        let start = from.advanced(by: offset.height * fromRow + offset.width * 4)
        for row in 0..<height {
            memcpy(to.advanced(by: row * toRow), start.advanced(by: row * fromRow), width * 4)
        }
        return ViewerFrame(pixelBuffer: copy, layout: kept, displayID: displayID)
    }

    /// An IOSurface-backed, Metal-compatible BGRA buffer, drawn like a live frame.
    static func makeBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        let attributes: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [CFString: Any](),
            kCVPixelBufferMetalCompatibilityKey: true,
        ]
        var buffer: CVPixelBuffer?
        guard
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer)
                == kCVReturnSuccess
        else { return nil }
        return buffer
    }
}

/// The latest complete frame, handed from the ScreenCaptureKit queue to the main thread, and the
/// still frames the Viewer shows in place of it.
///
/// The capture queue writes, the renderer and the exporters read. The lock guards every property;
/// nothing else is shared (docs/design.md §2.2).
final class FrameStore: @unchecked Sendable {
    private let lock = NSLock()
    private var frame: ViewerFrame?
    private var geometry: CaptureGeometry?
    private var frozen: ViewerFrame?
    private var capture: ViewerFrame?
    private var held: ViewerFrame?
    /// When the stream took `geometry` on (host time); `nil` until it has.
    private var configuredAt: UInt64?
    /// Whether `frame` was captured after that (`MagnetHold.isCaptured`).
    private var frameIsCurrent = false

    /// Freezing keeps the live frame as a still, so the Viewer, the Color Meter and Copy/Save all
    /// keep the frame that was showing (docs/product.md, Freeze frame). Setting it while frozen
    /// keeps the frame frozen first; without a live frame there is nothing to freeze. Freezing
    /// during a hold freezes the held frame and ends the hold.
    var isFrozen: Bool {
        get { lock.withLock { frozen != nil } }
        set {
            lock.withLock {
                frozen = newValue ? frozen ?? held ?? frame : nil
                if newValue { held = nil }
            }
        }
    }

    /// Whether the Viewer holds a live frame while the magnet moves the area (`MagnetHold`).
    var isHolding: Bool {
        lock.withLock { held != nil }
    }

    /// Holds the live frame the Viewer shows: `shownFrame` keeps it while live frames go on being
    /// stored. Nothing to hold under a still picture or without a live frame.
    func hold() {
        lock.withLock { if capture == nil, frozen == nil, held == nil { held = frame } }
    }

    func releaseHold() {
        lock.withLock { held = nil }
    }

    /// Whether the latest live frame shows `area`, the area where it is now (`MagnetHold.frameShows`).
    func latestFrameShows(_ area: CaptureGeometry?) -> Bool {
        lock.withLock {
            MagnetHold.frameShows(area, frameGeometry: frame?.geometry, capturedAfterConfiguring: frameIsCurrent)
        }
    }

    /// A recent capture, or an opened image, shown in place of the live frame (docs/product.md,
    /// Recent Captures, Open Image). Above a frozen frame, which comes back when it goes.
    var shownCapture: ViewerFrame? {
        get { lock.withLock { capture } }
        set { lock.withLock { capture = newValue } }
    }

    /// What the Viewer shows in place of the live frame: a recent capture or an opened image, or else
    /// the frozen frame. `nil` while it is live. Live frames are still stored meanwhile, so the view
    /// is current when it goes back to live.
    var still: ViewerFrame? {
        lock.withLock { capture ?? frozen }
    }

    /// The frame Take Snapshot keeps (`RecentCaptureRules.snapshotFrame`): the one the live view shows,
    /// whatever shows in its place.
    var snapshotFrame: ViewerFrame? {
        lock.withLock { RecentCaptureRules.snapshotFrame(frozen: frozen, held: held, live: frame) }
    }

    /// The frame the Viewer shows: the still one, or else the held one, or else the latest live frame.
    var shownFrame: ViewerFrame? {
        lock.withLock { capture ?? frozen ?? held ?? frame }
    }

    /// The geometry the stream is currently configured with. Frames arriving from now on carry it.
    /// `configuredAt` is when the stream took it on (host time): 0 for a new stream, whose every
    /// frame has it; `nil` while an update of a running stream is in flight (`geometryTookEffect`).
    func setGeometry(_ geometry: CaptureGeometry?, configuredAt: UInt64? = nil) {
        lock.withLock {
            self.geometry = geometry
            self.configuredAt = configuredAt
            if geometry == nil { frame = nil }
        }
    }

    /// The running stream's update to `geometry` finished at `time` (host time): frames captured
    /// since have its source rect.
    func geometryTookEffect(_ geometry: CaptureGeometry, at time: UInt64) {
        lock.withLock { if self.geometry == geometry { configuredAt = time } }
    }

    /// Stores a buffer from the stream, captured at `capturedAt` (host time). Returns `false` when no
    /// geometry is set (the stream is stopping) or the buffer doesn't match it (a frame from before
    /// the last reconfiguration).
    func store(_ pixelBuffer: CVPixelBuffer, capturedAt: UInt64?) -> Bool {
        lock.withLock {
            let size = PixelSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
            guard let geometry, size == geometry.outputSize else {
                #if DEBUG
                    stats.rejected += 1
                #endif
                return false
            }
            frame = ViewerFrame(pixelBuffer: pixelBuffer, geometry: geometry)
            frameIsCurrent = MagnetHold.isCaptured(at: capturedAt, afterConfiguringAt: configuredAt)
            #if DEBUG
                stats.stored += 1
            #endif
            return true
        }
    }

    #if DEBUG
        /// Counters for the debug log: where frames go between ScreenCaptureKit and the screen.
        struct Stats: Equatable {
            var callbacks = 0
            var complete = 0
            var stored = 0
            var rejected = 0
            /// `draw(in:)` calls, including those that got no drawable.
            var drawCalls = 0
            var draws = 0
        }

        private var stats = Stats()

        /// Returns the counters since the last call and resets them.
        func takeStats() -> Stats {
            lock.withLock {
                defer { stats = Stats() }
                return stats
            }
        }

        func count(_ update: (inout Stats) -> Void) {
            lock.withLock { update(&stats) }
        }
    #endif
}
