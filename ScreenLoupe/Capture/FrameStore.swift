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
}

/// The latest complete frame, handed from the ScreenCaptureKit queue to the main thread.
///
/// The capture queue writes, the renderer and the exporters read. The lock guards both properties;
/// nothing else is shared (docs/design.md §2.2).
final class FrameStore: @unchecked Sendable {
    /// Counters for the debug log: where frames go between ScreenCaptureKit and the screen.
    struct Stats: Equatable {
        var callbacks = 0
        var complete = 0
        var stored = 0
        var rejected = 0
        /// `draw(in:)` calls, including those that got no drawable.
        var drawCalls = 0
        var draws = 0
        var drawsWithFrame = 0
    }

    private let lock = NSLock()
    private var frame: CapturedFrame?
    private var geometry: CaptureGeometry?
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

    var latestFrame: CapturedFrame? {
        lock.withLock { frame }
    }

    /// The geometry the stream is currently configured with. Frames arriving from now on carry it.
    func setGeometry(_ geometry: CaptureGeometry?) {
        lock.withLock {
            self.geometry = geometry
            if geometry == nil { frame = nil }
        }
    }

    /// Stores a buffer from the stream. Returns `false` when no geometry is set (the stream is
    /// stopping) or the buffer doesn't match it (a frame from before the last reconfiguration).
    func store(_ pixelBuffer: CVPixelBuffer) -> Bool {
        lock.withLock {
            let size = PixelSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
            guard let geometry, size == geometry.outputSize else {
                stats.rejected += 1
                return false
            }
            frame = CapturedFrame(pixelBuffer: pixelBuffer, geometry: geometry)
            stats.stored += 1
            return true
        }
    }
}
