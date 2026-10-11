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
    /// The colour space the pixels are in, kept with them: an opened image's own, or a recent
    /// capture's, its display's as it was taken, since the display may go or change its profile.
    /// `nil` for a frame of the stream, whose colour space is its display's (`colorSpace`).
    let imageColorSpace: CGColorSpace?
    /// The geometry the stream captured it with: a live frame, or one frozen from it. A recent
    /// capture or an opened image is a picture of its own, whose pixels don't map onto the Capture
    /// Area, so it has none: the crosshair, the cursor, the part the Viewer shows and following the
    /// area's edges don't apply to it.
    let geometry: CaptureGeometry?

    /// Whether the buffer's alpha is the picture's own, straight (not premultiplied): an opened
    /// image's transparency. Frames of the screen are opaque, whatever their alpha bytes hold.
    let hasAlpha: Bool

    /// Where the picture's top-left sits in the Capture Area, in its pixels: a snapshot's kept part
    /// where it was taken (`RecentCaptureRules.snapshotOrigin`); the area's corner for a frame of
    /// the stream, the whole area, and for an image, which has no place in it. Reference layers are
    /// placed in the area, and shown over the picture through it (`PictureInArea`).
    var areaOrigin: CGPoint

    /// Where the picture lies in `pixelBuffer`, in its pixels: all of it, or for a part of a larger
    /// capture (`part(_:)`) just that part. Everything that reads the pixels reads them here.
    let bufferRect: PixelRect

    /// Whether the frame is a part of a larger capture (`part(_:)`), as a copy of it keeps
    /// (`keepingOnlyItsPart`): the picture of an area that moves as a whole, never by an edge
    /// (`AreaResizeTracker`).
    let isPart: Bool

    init(
        pixelBuffer: CVPixelBuffer, layout: FrameLayout, displayID: CGDirectDisplayID?,
        imageColorSpace: CGColorSpace? = nil, hasAlpha: Bool = false, areaOrigin: CGPoint = .zero
    ) {
        self.pixelBuffer = pixelBuffer
        self.layout = layout
        self.displayID = displayID
        self.imageColorSpace = imageColorSpace
        self.hasAlpha = hasAlpha
        self.areaOrigin = areaOrigin
        geometry = nil
        bufferRect = Self.wholeRect(of: pixelBuffer)
        isPart = false
    }

    /// A frame of the stream.
    init(pixelBuffer: CVPixelBuffer, geometry: CaptureGeometry) {
        self.init(
            pixelBuffer: pixelBuffer, geometry: geometry, bufferRect: Self.wholeRect(of: pixelBuffer), isPart: false)
    }

    private init(pixelBuffer: CVPixelBuffer, geometry: CaptureGeometry, bufferRect: PixelRect, isPart: Bool) {
        self.pixelBuffer = pixelBuffer
        layout = geometry.layout
        displayID = geometry.display.id
        imageColorSpace = nil
        hasAlpha = false
        areaOrigin = .zero
        self.geometry = geometry
        self.bufferRect = bufferRect
        self.isPart = isPart
    }

    private static func wholeRect(of buffer: CVPixelBuffer) -> PixelRect {
        PixelRect(x: 0, y: 0, width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
    }

    /// The picture's size in pixels: `bufferRect`'s.
    var pixelSize: PixelSize { bufferRect.size }

    /// This frame of the stream as just `part` of what it captured, a frame of `part`'s geometry
    /// read from the same buffer (`CaptureGeometry.pixelRect(of:)`); `nil` when `part` isn't inside
    /// it.
    func part(_ part: CaptureGeometry) -> ViewerFrame? {
        guard let geometry, let rect = geometry.pixelRect(of: part) else { return nil }
        return ViewerFrame(
            pixelBuffer: pixelBuffer, geometry: part,
            bufferRect: PixelRect(
                x: bufferRect.x + rect.x, y: bufferRect.y + rect.y, width: rect.width, height: rect.height),
            isPart: true)
    }

    /// Calls `body` with the picture's pixels, 32-bit BGRA: the address of its top-left pixel, the
    /// bytes from one row to the next, and its size. `nil` when the buffer can't be read. The
    /// pixels are valid only during the call.
    func withPixels<Result>(_ body: (UnsafeRawPointer, Int, PixelSize) -> Result?) -> Result? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let start = base.advanced(by: bufferRect.y * bytesPerRow + bufferRect.x * 4)
        return body(UnsafeRawPointer(start), bytesPerRow, pixelSize)
    }

    /// The frame copied into a buffer of its own, cut to `area` (whole pixels of the picture: what a
    /// snapshot keeps) and to `ImageBudget`, to keep as a recent capture. The stream's buffers come
    /// from a small pool it reuses; holding on to them would starve it. IOSurface-backed and
    /// Metal-compatible, so it is drawn like a live frame. It keeps `colorSpace`, its display's now.
    func copiedForKeeping(area: CGRect, colorSpace: CGColorSpace) -> ViewerFrame? {
        guard let cut = layout.cropped(toArea: area), let kept = cut.layout.fittedToImageBudget() else { return nil }
        let offset = cut.offset
        let width = kept.imageSize.width
        let height = kept.imageSize.height
        guard let copy = Self.makeBuffer(width: width, height: height) else { return nil }
        CVPixelBufferLockBaseAddress(copy, [])
        defer { CVPixelBufferUnlockBaseAddress(copy, []) }
        guard let to = CVPixelBufferGetBaseAddress(copy) else { return nil }
        let toRow = CVPixelBufferGetBytesPerRow(copy)
        let copied: Bool? = withPixels { from, fromRow, _ in
            // The kept image starts at `offset` in the captured one.
            PictureRows.copy(
                from.advanced(by: offset.height * fromRow + offset.width * 4), sourceRow: fromRow, to: to,
                destinationRow: toRow, width: width, height: height)
            return true
        }
        guard copied == true else { return nil }
        return ViewerFrame(
            pixelBuffer: copy, layout: kept, displayID: nil, imageColorSpace: colorSpace,
            areaOrigin: PictureInArea.areaPoint(
                RecentCaptureRules.snapshotOrigin(area: area), pictureOrigin: areaOrigin))
    }

    /// A frame that is a part of a larger buffer (`part(_:)`) copied into a buffer of its own, with
    /// its geometry: what is kept of it, such as a frozen frame, holds just the part, not the
    /// stream's buffer of the whole capture. A frame that is its whole buffer, or one that can't be
    /// copied, as it is.
    func keepingOnlyItsPart() -> ViewerFrame {
        let size = pixelSize
        guard let geometry, bufferRect != Self.wholeRect(of: pixelBuffer),
            let copy = Self.makeBuffer(width: size.width, height: size.height)
        else { return self }
        CVPixelBufferLockBaseAddress(copy, [])
        defer { CVPixelBufferUnlockBaseAddress(copy, []) }
        guard let to = CVPixelBufferGetBaseAddress(copy) else { return self }
        let toRow = CVPixelBufferGetBytesPerRow(copy)
        let copied: Bool? = withPixels { from, fromRow, size in
            PictureRows.copy(
                from, sourceRow: fromRow, to: to, destinationRow: toRow, width: size.width, height: size.height)
            return true
        }
        guard copied == true else { return self }
        return ViewerFrame(
            pixelBuffer: copy, geometry: geometry, bufferRect: Self.wholeRect(of: copy), isPart: true)
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
/// nothing else is shared.
final class FrameStore: @unchecked Sendable {
    private let lock = NSLock()
    private var frame: ViewerFrame?
    private var geometry: CaptureGeometry?
    private var frozen: ViewerFrame?
    /// When the view was frozen.
    private var frozenAt = Date.distantPast
    private var capture: ViewerFrame?
    private var held: ViewerFrame?
    /// When the stream took `geometry` on (host time); `nil` until it has.
    private var configuredAt: UInt64?
    /// Whether `frame` was captured after that (`MagnetHold.isCaptured`).
    private var frameIsCurrent = false
    private var part: CaptureGeometry?
    /// The live frame last shown while the latest frame can't give one — the part isn't inside it
    /// (a frame of another display), or none came since the part was cleared — so the Viewer keeps
    /// showing it until a frame that can arrives, as it keeps its picture while the Capture Area
    /// moves.
    private var lastLive: ViewerFrame?

    /// A part of what the stream captures that the live view shows in place of all of it: every
    /// live frame is then just this part of the latest captured one (`ViewerFrame.part`), so the
    /// Viewer, Freeze, Take Snapshot and every reader of the shown frame see only it, and none
    /// the last one shown while it isn't inside that frame. `nil`, the default, shows all the stream
    /// captures. Clearing it drops the latest frame, which is of more than the live view shows from
    /// now on; the last part shown stays until the next frame.
    var livePart: CaptureGeometry? {
        get { lock.withLock { part } }
        set {
            lock.withLock {
                if newValue == nil, let part {
                    lastLive = frame?.part(part) ?? lastLive
                    frame = nil
                } else if newValue != nil, part == nil {
                    lastLive = frame
                }
                part = newValue
            }
        }
    }

    /// The live frame: the latest one, or the part of it `livePart` asks for; else the last one
    /// shown (`lastLive`). Called under the lock.
    private var live: ViewerFrame? {
        if let part {
            if let shown = frame?.part(part) {
                lastLive = shown
                return shown
            }
            return lastLive
        }
        if let frame {
            lastLive = nil
            return frame
        }
        return lastLive
    }

    /// Freezing keeps the live frame as a still, so the Viewer, the Color Meter and Copy/Save all
    /// keep the frame that was showing. Setting it while frozen
    /// keeps the frame frozen first; without a live frame there is nothing to freeze. Freezing
    /// during a hold freezes the held frame and ends the hold.
    var isFrozen: Bool {
        get { lock.withLock { frozen != nil } }
        set {
            lock.withLock {
                let wasFrozen = frozen != nil
                // A part of a capture is kept as a copy of just the part.
                frozen = newValue ? frozen ?? held ?? live?.keepingOnlyItsPart() : nil
                if newValue { held = nil }
                if !wasFrozen, frozen != nil { frozenAt = Date() }
            }
        }
    }

    /// The frozen frame and when it was frozen, for Use Frozen Frame as Reference; `nil` while live.
    var frozenFrame: (frame: ViewerFrame, date: Date)? {
        lock.withLock { frozen.map { ($0, frozenAt) } }
    }

    /// Whether the Viewer holds a live frame while the magnet moves the area (`MagnetHold`).
    var isHolding: Bool {
        lock.withLock { held != nil }
    }

    /// Holds the live frame the Viewer shows: `shownFrame` keeps it while live frames go on being
    /// stored. Nothing to hold under a still picture or without a live frame.
    func hold() {
        lock.withLock { if capture == nil, frozen == nil, held == nil { held = live } }
    }

    func releaseHold() {
        lock.withLock { held = nil }
    }

    /// Whether the latest live frame shows `area`, the area where it is now (`MagnetHold.frameShows`).
    func latestFrameShows(_ area: CaptureGeometry?) -> Bool {
        lock.withLock {
            MagnetHold.frameShows(area, frameGeometry: live?.geometry, capturedAfterConfiguring: frameIsCurrent)
        }
    }

    /// A recent capture, or an opened image, shown in place of the live frame. Above a frozen frame, which comes back
    /// when it goes.
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
        lock.withLock { RecentCaptureRules.snapshotFrame(frozen: frozen, held: held, live: live) }
    }

    /// The frame the Viewer shows: the still one, or else the held one, or else the latest live frame.
    var shownFrame: ViewerFrame? {
        lock.withLock { capture ?? frozen ?? held ?? live }
    }

    /// The geometry the stream is currently configured with. Frames arriving from now on carry it.
    /// `configuredAt` is when the stream took it on (host time): 0 for a new stream, whose every
    /// frame has it; `nil` while an update of a running stream is in flight (`geometryTookEffect`).
    func setGeometry(_ geometry: CaptureGeometry?, configuredAt: UInt64? = nil) {
        lock.withLock {
            self.geometry = geometry
            self.configuredAt = configuredAt
            if geometry == nil {
                frame = nil
                // Without a part the stream stops for good; with one it moves to another display.
                if part == nil { lastLive = nil }
            }
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
