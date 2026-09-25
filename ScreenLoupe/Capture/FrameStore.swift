import CoreVideo
import Foundation

/// A captured frame and the geometry it was captured with.
struct CapturedFrame: @unchecked Sendable {
    /// IOSurface-backed BGRA buffer. Never written to after capture, so sharing it across threads is
    /// safe; that is why the struct is `@unchecked Sendable`.
    let pixelBuffer: CVPixelBuffer
    let geometry: CaptureGeometry

    var pixelSize: PixelSize {
        PixelSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
    }

    /// The frame copied into a buffer of its own, cut to `area` (whole pixels of the Capture Area,
    /// for a selection or a region) and to `ImageBudget`, to keep as a recent capture. The stream's
    /// buffers come from a small pool it reuses; holding on to them would starve it.
    /// IOSurface-backed and Metal-compatible, so it is drawn like a live frame.
    func copiedForKeeping(area: CGRect? = nil) -> CapturedFrame? {
        var cut = geometry
        var offset = PixelSize(width: 0, height: 0)
        if let area {
            guard let cropped = geometry.cropped(toArea: area) else { return nil }
            (cut, offset) = cropped
        }
        guard let kept = cut.fittedToImageBudget() else { return nil }
        let width = kept.outputSize.width
        let height = kept.outputSize.height
        let attributes: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [CFString: Any](),
            kCVPixelBufferMetalCompatibilityKey: true,
        ]
        var copy: CVPixelBuffer?
        guard
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &copy)
                == kCVReturnSuccess,
            let copy
        else { return nil }
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
        return CapturedFrame(pixelBuffer: copy, geometry: kept)
    }
}

/// The latest complete frame, handed from the ScreenCaptureKit queue to the main thread.
///
/// The capture queue writes, the renderer and the exporters read. The lock guards both properties;
/// nothing else is shared (docs/design.md §2.2).
final class FrameStore: @unchecked Sendable {
    private let lock = NSLock()
    private var frame: CapturedFrame?
    private var geometry: CaptureGeometry?
    private var frozen = false
    private var capture: CapturedFrame?

    /// While frozen, new frames are dropped, so the Viewer, the Color Meter and Copy/Save all keep
    /// the frame that was showing (docs/product.md, Freeze frame).
    var isFrozen: Bool {
        get { lock.withLock { frozen } }
        set { lock.withLock { frozen = newValue } }
    }

    /// A recent capture shown in place of the live frame (docs/product.md, Recent Captures): the
    /// Viewer, the Color Meter and Copy/Save all take it, as they take a frozen frame. Live frames
    /// are still stored meanwhile, so the view is current when it goes back to live.
    var shownCapture: CapturedFrame? {
        get { lock.withLock { capture } }
        set { lock.withLock { capture = newValue } }
    }

    var latestFrame: CapturedFrame? {
        lock.withLock { capture ?? frame }
    }

    /// The geometry the stream is currently configured with. Frames arriving from now on carry it.
    func setGeometry(_ geometry: CaptureGeometry?) {
        lock.withLock {
            self.geometry = geometry
            // A frozen frame outlives a stream that stops or restarts under it.
            if geometry == nil, !frozen { frame = nil }
        }
    }

    /// Stores a buffer from the stream. Returns `false` while frozen, when no geometry is set (the
    /// stream is stopping) or the buffer doesn't match it (a frame from before the last
    /// reconfiguration).
    func store(_ pixelBuffer: CVPixelBuffer) -> Bool {
        lock.withLock {
            let size = PixelSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
            guard !frozen, let geometry, size == geometry.outputSize else {
                #if DEBUG
                    stats.rejected += 1
                #endif
                return false
            }
            frame = CapturedFrame(pixelBuffer: pixelBuffer, geometry: geometry)
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
