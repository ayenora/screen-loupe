import AppKit
import OSLog
@preconcurrency import ScreenCaptureKit

/// Why the capture isn't running although it should be.
enum CaptureProblem: Equatable {
    /// ScreenCaptureKit refused for lack of Screen Recording access, even if the preflight check said
    /// otherwise (it can be stale until the app relaunches).
    case permissionDenied
    case failed(String)
}

/// Streams the Capture Area with ScreenCaptureKit into a `FrameStore` (docs/design.md §2.1).
///
/// One stream captures one display, excluding every window of this app. Moving or resizing the area
/// reconfigures the running stream; moving it to another display replaces the stream. Updates are
/// coalesced: at most one is in flight, and the newest geometry wins.
@MainActor
final class ScreenCaptureManager: NSObject {
    let frameStore = FrameStore()
    /// Called on the main actor after a new frame lands in `frameStore`.
    var onFrame: (() -> Void)?
    /// Called when the user stops the capture from the system's screen-sharing menu. Capturing stays
    /// off until `capture(_:)` is called again.
    var onUserStopped: (() -> Void)?
    /// Called when a problem appears (`CaptureProblem`) or goes away (`nil`).
    var onProblem: ((CaptureProblem?) -> Void)?

    private let log = Logger(subsystem: "com.ayenora.screenloupe", category: "capture")
    private let sampleQueue = DispatchQueue(label: "com.ayenora.screenloupe.capture", qos: .userInteractive)

    private var stream: SCStream?
    /// The running stream's output. Each stream gets its own, removed again when the stream stops.
    private var output: StreamOutput?
    private var streamDisplayID: CGDirectDisplayID?
    private var content: SCShareableContent?
    /// What the area needs captured.
    private var wanted: CaptureGeometry?
    /// What the running stream was last set up for — or, after a failure, what was last tried, so
    /// the same geometry isn't retried in a loop.
    private var applied: CaptureGeometry?
    private var isUpdating = false
    /// Bumped whenever something outside the update in flight invalidates what it is doing: the system
    /// stopped the stream, or the displays changed. An update that finishes under an older generation
    /// doesn't record its result, so the next pass starts over.
    private var generation = 0
    private var problem: CaptureProblem? {
        didSet { if problem != oldValue { onProblem?(problem) } }
    }
    private var retryTask: Task<Void, Never>?

    /// Captures `geometry`, or stops when it is `nil`.
    func capture(_ geometry: CaptureGeometry?) {
        wanted = geometry
        if geometry == nil { problem = nil }
        processUpdates()
    }

    /// Displays were added, removed or rearranged: re-read them before the next update.
    func displaysChanged() {
        invalidate()
        processUpdates()
    }

    /// Tries the current geometry again after a failure.
    func retry() {
        invalidate()
        processUpdates()
    }

    private func invalidate() {
        generation += 1
        content = nil
        applied = nil
    }

    private func processUpdates() {
        guard !isUpdating, wanted != applied else { return }
        isUpdating = true
        let target = wanted
        let startedGeneration = generation
        Task {
            await self.apply(target)
            if self.generation != startedGeneration {
                self.applied = nil
            }
            self.isUpdating = false
            self.processUpdates()
        }
    }

    private func apply(_ geometry: CaptureGeometry?) async {
        retryTask?.cancel()
        guard let geometry else {
            await stop()
            applied = nil
            return
        }
        let started = ContinuousClock.now
        do {
            let content = try await shareableContent()
            guard let display = content.displays.first(where: { $0.displayID == geometry.display.id }) else {
                // AppKit can know a new display before ScreenCaptureKit lists it. Give it a second
                // rather than asking again at once.
                log.error("Display \(geometry.display.id) not in shareable content yet")
                applied = geometry
                retryLater()
                return
            }
            let configuration = Self.configuration(for: geometry)
            if let stream, streamDisplayID == display.displayID {
                frameStore.setGeometry(geometry)
                try await stream.updateConfiguration(configuration)
            } else {
                // A new display gets a new stream: swapping the filter of a running stream would apply
                // the old display's source rect to the new display until the configuration follows.
                await stop()
                frameStore.setGeometry(geometry)
                try await start(display, in: content, configuration: configuration)
            }
            applied = geometry
            problem = nil
            let elapsed = ContinuousClock.now - started
            log.debug("Stream updated in \(elapsed.formatted(.units(allowed: [.milliseconds])), privacy: .public)")
        } catch {
            log.error("Capture update failed: \(error.localizedDescription, privacy: .public)")
            await stop()
            applied = geometry
            problem = Self.problem(for: error)
        }
    }

    private func retryLater() {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.retry()
        }
    }

    private static func problem(for error: any Error) -> CaptureProblem {
        let nsError = error as NSError
        if nsError.domain == SCStreamErrorDomain, nsError.code == SCStreamError.userDeclined.rawValue {
            return .permissionDenied
        }
        return .failed(error.localizedDescription)
    }

    private func start(
        _ display: SCDisplay, in content: SCShareableContent, configuration: SCStreamConfiguration
    ) async throws {
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
        #if DEBUG
            startStatsLog()
        #endif
    }

    private func stop() async {
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
        #if DEBUG
            statsTimer?.invalidate()
            statsTimer = nil
        #endif
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

    // MARK: Debug statistics

    #if DEBUG
        private var statsTimer: Timer?

        /// Once a second while streaming: how many frames came in, were kept and were drawn.
        private func startStatsLog() {
            guard statsTimer == nil else { return }
            _ = frameStore.takeStats()
            statsTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let s = self.frameStore.takeStats()
                    self.log.debug(
                        "Frames/s: callbacks \(s.callbacks) complete \(s.complete) stored \(s.stored) rejected \(s.rejected) · draw calls \(s.drawCalls) draws \(s.draws)"
                    )
                }
            }
        }
    #endif
}

extension ScreenCaptureManager: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        let nsError = error as NSError
        let stoppedByUser = nsError.domain == SCStreamErrorDomain && nsError.code == SCStreamError.userStopped.rawValue
        Task { @MainActor in
            guard self.stream === stream else { return }
            // The stream has already stopped; only its output needs removing.
            await self.detach(stream, stopCapture: false)
            self.frameStore.setGeometry(nil)
            if stoppedByUser {
                // The user's choice: don't restart behind their back.
                self.log.info("Stream stopped by the user")
                self.wanted = nil
                self.applied = nil
                self.onUserStopped?()
                return
            }
            // Stopped by the system, typically a display was unplugged: start over from the current
            // display list, even if an update is in flight right now.
            self.log.error("Stream stopped: \(error.localizedDescription, privacy: .public)")
            self.invalidate()
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
        #if DEBUG
            frameStore.count { $0.callbacks += 1 }
        #endif
        guard type == .screen, sampleBuffer.isValid, Self.isComplete(sampleBuffer),
            let pixelBuffer = sampleBuffer.imageBuffer
        else { return }
        #if DEBUG
            frameStore.count { $0.complete += 1 }
        #endif
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
