import AppKit
import OSLog
@preconcurrency import ScreenCaptureKit

/// Streams the Capture Area with ScreenCaptureKit into a `FrameStore` (docs/design.md §2.1).
///
/// One stream captures one display, excluding every window of this app. Moving or resizing the area
/// reconfigures the running stream; moving it to another display swaps the content filter. Updates are
/// coalesced: at most one is in flight, and the newest geometry wins.
@MainActor
final class ScreenCaptureManager: NSObject {
    let frameStore = FrameStore()
    /// Called on the main actor after a new frame lands in `frameStore`.
    var onFrame: (() -> Void)?
    /// Called when the user stops the capture from the system's screen-sharing menu. Capturing stays
    /// off until `capture(_:)` is called again.
    var onUserStopped: (() -> Void)?

    private let log = Logger(subsystem: "com.ayenora.screenloupe", category: "capture")
    private let sampleQueue = DispatchQueue(label: "com.ayenora.screenloupe.capture", qos: .userInteractive)

    private var stream: SCStream?
    /// The running stream's output. Each stream gets its own, removed again when the stream stops.
    private var output: StreamOutput?
    private var streamDisplayID: CGDirectDisplayID?
    private var content: SCShareableContent?
    private var wanted: CaptureGeometry?
    private var applied: CaptureGeometry?
    private var isUpdating = false
    private var statsTimer: Timer?

    /// Captures `geometry`, or stops when it is `nil`.
    func capture(_ geometry: CaptureGeometry?) {
        wanted = geometry
        processUpdates()
    }

    /// Displays were added, removed or rearranged: re-read them before the next update.
    func displaysChanged() {
        content = nil
        applied = nil
        processUpdates()
    }

    private func processUpdates() {
        guard !isUpdating, wanted != applied else { return }
        isUpdating = true
        let target = wanted
        Task {
            await self.apply(target)
            self.isUpdating = false
            self.processUpdates()
        }
    }

    private func apply(_ geometry: CaptureGeometry?) async {
        guard let geometry else {
            await stop()
            applied = nil
            return
        }
        let started = ContinuousClock.now
        do {
            let content = try await shareableContent()
            guard let display = content.displays.first(where: { $0.displayID == geometry.display.id }) else {
                // The display list is stale; read it again on the next pass.
                self.content = nil
                log.error("Display \(geometry.display.id) not found in shareable content")
                applied = nil
                return
            }
            let configuration = Self.configuration(for: geometry)
            frameStore.setGeometry(geometry)
            if let stream {
                if streamDisplayID != display.displayID {
                    try await stream.updateContentFilter(filter(for: display, in: content))
                    streamDisplayID = display.displayID
                }
                try await stream.updateConfiguration(configuration)
            } else {
                try await start(display, in: content, configuration: configuration)
            }
            applied = geometry
            let elapsed = ContinuousClock.now - started
            log.debug("Stream updated in \(elapsed.formatted(.units(allowed: [.milliseconds])), privacy: .public)")
        } catch {
            log.error("Capture update failed: \(error.localizedDescription, privacy: .public)")
            await stop()
            // Don't retry the same geometry in a loop; the next change of the area tries again.
            applied = geometry
        }
    }

    private func start(
        _ display: SCDisplay, in content: SCShareableContent, configuration: SCStreamConfiguration
    )
        async throws
    {
        let stream = SCStream(filter: filter(for: display, in: content), configuration: configuration, delegate: self)
        let output = StreamOutput(frameStore: frameStore) { [weak self] in
            Task { @MainActor in self?.onFrame?() }
        }
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: sampleQueue)
        self.stream = stream
        self.output = output
        streamDisplayID = display.displayID
        try await stream.startCapture()
        log.info("Stream started on display \(display.displayID)")
        startStatsLog()
    }

    /// Once a second while streaming: how many frames came in, were kept and were drawn.
    private func startStatsLog() {
        guard statsTimer == nil else { return }
        _ = frameStore.takeStats()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let s = self.frameStore.takeStats()
                self.log.debug(
                    "Frames/s: callbacks \(s.callbacks) complete \(s.complete) stored \(s.stored) rejected \(s.rejected) · draw calls \(s.drawCalls) draws \(s.draws) (with frame \(s.drawsWithFrame))"
                )
            }
        }
    }

    private func stop() async {
        statsTimer?.invalidate()
        statsTimer = nil
        frameStore.setGeometry(nil)
        guard let stream else { return }
        await detach(stream, stopCapture: true)
        log.info("Stream stopped")
    }

    /// Forgets `stream` and removes its output, so nothing of it carries over to the next stream.
    private func detach(_ stream: SCStream, stopCapture: Bool) async {
        if let output {
            try? stream.removeStreamOutput(output, type: .screen)
        }
        self.stream = nil
        self.output = nil
        streamDisplayID = nil
        if stopCapture {
            try? await stream.stopCapture()
        }
    }

    private func shareableContent() async throws -> SCShareableContent {
        if let content { return content }
        let fresh = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        content = fresh
        return fresh
    }

    /// The whole display minus every window of this app: the Capture Area frame and the Viewer never
    /// show up in the capture, wherever they are (docs/design.md §2.1).
    private func filter(for display: SCDisplay, in content: SCShareableContent) -> SCContentFilter {
        let pid = ProcessInfo.processInfo.processIdentifier
        if let app = content.applications.first(where: { $0.processID == pid }) {
            return SCContentFilter(display: display, excludingApplications: [app], exceptingWindows: [])
        }
        // Fallback (docs/design.md §6, risk 4): exclude our windows one by one.
        let ours = content.windows.filter { $0.owningApplication?.processID == pid }
        log.info("App not in shareable content; excluding \(ours.count) windows instead")
        return SCContentFilter(display: display, excludingWindows: ours)
    }

    private static func configuration(for geometry: CaptureGeometry) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = geometry.sourceRect.rect
        configuration.width = geometry.outputSize.width
        configuration.height = geometry.outputSize.height
        configuration.captureResolution = .best
        configuration.scalesToFit = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.queueDepth = 5
        return configuration
    }
}

extension ScreenCaptureManager: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        let nsError = error as NSError
        let stoppedByUser = nsError.domain == SCStreamErrorDomain && nsError.code == SCStreamError.userStopped.rawValue
        Task { @MainActor in
            guard self.stream === stream else { return }
            // The stream has already stopped; only its output needs removing.
            await self.detach(stream, stopCapture: false)
            self.applied = nil
            if stoppedByUser {
                // The user's choice: don't restart behind their back.
                self.log.info("Stream stopped by the user")
                self.wanted = nil
                self.frameStore.setGeometry(nil)
                self.onUserStopped?()
                return
            }
            // Stopped by the system, typically a display was unplugged: start over from the current
            // display list.
            self.log.error("Stream stopped: \(error.localizedDescription, privacy: .public)")
            self.content = nil
            self.processUpdates()
        }
    }
}

/// Receives sample buffers on the capture queue and keeps the latest complete frame.
private final class StreamOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    private let frameStore: FrameStore
    private let frameArrived: @Sendable () -> Void

    init(frameStore: FrameStore, frameArrived: @escaping @Sendable () -> Void) {
        self.frameStore = frameStore
        self.frameArrived = frameArrived
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        frameStore.count { $0.callbacks += 1 }
        guard type == .screen, sampleBuffer.isValid, Self.isComplete(sampleBuffer),
            let pixelBuffer = sampleBuffer.imageBuffer
        else { return }
        frameStore.count { $0.complete += 1 }
        if frameStore.store(pixelBuffer) {
            frameArrived()
        }
    }

    /// Idle frames (nothing changed) and blank frames carry no new image.
    private static func isComplete(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
            let rawStatus = attachments.first?[.status] as? Int,
            let status = SCFrameStatus(rawValue: rawStatus)
        else { return false }
        return status == .complete || status == .started
    }
}
