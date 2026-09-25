import AppKit
import OSLog
@preconcurrency import ScreenCaptureKit

/// Why the capture isn't running although it should be.
enum CaptureProblem: Equatable {
    /// ScreenCaptureKit refused for lack of Screen Recording access, even if the preflight check said
    /// otherwise (it can be stale until the app relaunches).
    case permissionDenied
    /// The capture broke and is being restored automatically. `nextAttempt` is `nil` while attempt
    /// number `attempt` is running, else when it starts.
    case reconnecting(reason: String, attempt: Int, maxAttempts: Int, nextAttempt: Date?)
    /// Every automatic attempt failed; only the user's Try Again starts over. `afterUserRetry`: that
    /// Try Again didn't help either, so a relaunch is the next thing to suggest.
    case failed(reason: String, afterUserRetry: Bool)
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

    private let log = Logger(category: "capture")
    private let sampleQueue = DispatchQueue(label: "\(Logger.subsystem).capture", qos: .userInteractive)

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
    /// Whether the running stream records the pointer, as last set up.
    private var appliedShowsCursor: Bool?
    private var isUpdating = false
    /// Bumped whenever something outside the update in flight invalidates what it is doing: the system
    /// stopped the stream, or the displays changed. An update that finishes under an older generation
    /// doesn't record its result, so the next pass starts over.
    private var generation = 0
    private var problem: CaptureProblem? {
        didSet { if problem != oldValue { onProblem?(problem) } }
    }
    private var retryTask: Task<Void, Never>?
    /// Failures in a row. The first few are retried on their own, with growing pauses: the capture
    /// service can take a moment to come back after its connection drops.
    private var consecutiveFailures = 0
    /// Attempts to restore a broken capture before giving up, the first one immediately.
    private static let maxAttempts = 4
    /// What broke the capture, shown while reconnecting.
    private var failureReason = ""
    /// The user pressed Try Again after the automatic attempts gave up.
    private var userRetried = false
    /// How long a ScreenCaptureKit call may take before it counts as failed.
    private static let callTimeout: Double = 5

    /// Captures `geometry`, or stops when it is `nil`.
    func capture(_ geometry: CaptureGeometry?) {
        wanted = geometry
        if geometry == nil { problem = nil }
        processUpdates()
    }

    /// Whether the capture records the real pointer into its pixels (docs/product.md, Crosshair and
    /// cursor: Original Cursor in the Capture). A running stream takes it with a configuration update.
    var showsCursor = false {
        didSet { if showsCursor != oldValue { processUpdates() } }
    }

    /// Displays were added, removed or rearranged: re-read them before the next update.
    func displaysChanged() {
        invalidate()
        processUpdates()
    }

    /// Tries the current geometry again now: Try Now while reconnecting, Try Again after giving up.
    func retry() {
        retryTask?.cancel()
        if case .reconnecting? = problem {
            // Try Now: this is the attempt the countdown was waiting for.
            markAttemptRunning()
        } else {
            if case .failed? = problem { userRetried = true }
            consecutiveFailures = 0
        }
        invalidate()
        processUpdates()
    }

    private func invalidate() {
        generation += 1
        content = nil
        applied = nil
    }

    private func processUpdates() {
        let cursorChanged = wanted != nil && showsCursor != appliedShowsCursor
        guard !isUpdating, wanted != applied || cursorChanged else { return }
        isUpdating = true
        let target = wanted
        let cursor = showsCursor
        let startedGeneration = generation
        Task {
            await self.apply(target, showsCursor: cursor)
            if self.generation != startedGeneration {
                self.applied = nil
            }
            self.isUpdating = false
            self.processUpdates()
        }
    }

    private func apply(_ geometry: CaptureGeometry?, showsCursor: Bool) async {
        retryTask?.cancel()
        guard let geometry else {
            await stop()
            applied = nil
            appliedShowsCursor = nil
            return
        }
        // Recorded first, like `applied` on every path: a failure isn't retried in a loop.
        appliedShowsCursor = showsCursor
        let started = ContinuousClock.now
        do {
            #if DEBUG
                if debugFailuresRemaining > 0 {
                    debugFailuresRemaining -= 1
                    throw NSError(
                        domain: "ScreenLoupe.Debug", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Simulated failure (Debug menu)."])
                }
            #endif
            let content = try await shareableContent()
            guard let display = content.displays.first(where: { $0.displayID == geometry.display.id }) else {
                // AppKit can know a new display before ScreenCaptureKit lists it. Give it a second
                // rather than asking again at once.
                log.error("Display \(geometry.display.id) not in shareable content yet")
                applied = geometry
                retryLater(after: 1)
                return
            }
            let configuration = Self.configuration(for: geometry, showsCursor: showsCursor)
            if let stream, streamDisplayID == display.displayID {
                frameStore.setGeometry(geometry)
                try await withTimeout(seconds: Self.callTimeout) { try await stream.updateConfiguration(configuration) }
            } else {
                // A new display gets a new stream: swapping the filter of a running stream would apply
                // the old display's source rect to the new display until the configuration follows.
                await stop()
                frameStore.setGeometry(geometry)
                try await start(display, in: content, configuration: configuration)
            }
            applied = geometry
            problem = nil
            consecutiveFailures = 0
            userRetried = false
            let elapsed = ContinuousClock.now - started
            log.debug("Stream updated in \(elapsed.formatted(.units(allowed: [.milliseconds])), privacy: .public)")
        } catch {
            log.error("Capture update failed: \(error.localizedDescription, privacy: .public)")
            await stop()
            applied = geometry
            consecutiveFailures += 1
            failureReason = error.localizedDescription
            if Self.isPermissionError(error) {
                problem = .permissionDenied
            } else if consecutiveFailures < Self.maxAttempts {
                let delay = Double(consecutiveFailures * 2)
                log.info("Retrying capture in \(delay) s")
                problem = .reconnecting(
                    reason: failureReason, attempt: consecutiveFailures + 1, maxAttempts: Self.maxAttempts,
                    nextAttempt: Date().addingTimeInterval(delay))
                retryLater(after: delay)
            } else {
                problem = .failed(reason: failureReason, afterUserRetry: userRetried)
            }
        }
    }

    private func retryLater(after seconds: Double) {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            markAttemptRunning()
            invalidate()
            processUpdates()
        }
    }

    /// While reconnecting: the attempt the countdown was waiting for starts now.
    private func markAttemptRunning() {
        if case .reconnecting(let reason, let attempt, let maxAttempts, _)? = problem {
            problem = .reconnecting(reason: reason, attempt: attempt, maxAttempts: maxAttempts, nextAttempt: nil)
        }
    }

    private static func isPermissionError(_ error: any Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == SCStreamErrorDomain && nsError.code == SCStreamError.userDeclined.rawValue
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
        try await withTimeout(seconds: Self.callTimeout) { try await stream.startCapture() }
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
            try? await withTimeout(seconds: Self.callTimeout) { try await stream.stopCapture() }
        }
    }

    private func shareableContent() async throws -> SCShareableContent {
        if let content { return content }
        let fresh = try await withTimeout(seconds: Self.callTimeout) {
            try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        }
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

    private static func configuration(for geometry: CaptureGeometry, showsCursor: Bool) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = geometry.sourceRect.rect
        configuration.width = geometry.outputSize.width
        configuration.height = geometry.outputSize.height
        configuration.captureResolution = .best
        configuration.scalesToFit = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        // Off unless asked for: the pointer would cover the pixels being inspected.
        configuration.showsCursor = showsCursor
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.queueDepth = 5
        return configuration
    }

    // MARK: Debug statistics

    #if DEBUG
        /// Attempts `simulateInterruption` still makes fail.
        fileprivate var debugFailuresRemaining = 0
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
            self.restartAfterSystemStop(reason: error.localizedDescription)
        }
    }

    /// Stopped by the system, typically a display was unplugged or the capture service's connection
    /// dropped: start over from the current display list, even if an update is in flight right now.
    /// The first attempt runs at once.
    fileprivate func restartAfterSystemStop(reason: String) {
        log.error("Stream stopped: \(reason, privacy: .public)")
        failureReason = reason
        consecutiveFailures = 0
        userRetried = false
        problem = .reconnecting(reason: reason, attempt: 1, maxAttempts: Self.maxAttempts, nextAttempt: nil)
        invalidate()
        processUpdates()
    }
}

#if DEBUG
    // MARK: Debug menu

    extension ScreenCaptureManager {
        /// Stops the stream as if the capture service's connection had dropped, so every state of the
        /// reconnecting panel can be checked by hand. When it `recovers`, the first attempt to restore
        /// it fails and the next one works. Otherwise every automatic attempt fails, and so does the
        /// first Try Again, which brings up the relaunch suggestion.
        func simulateInterruption(recovers: Bool) {
            debugFailuresRemaining = recovers ? 1 : 2 * Self.maxAttempts
            Task {
                await stop()
                restartAfterSystemStop(reason: "Simulated interruption (Debug menu).")
            }
        }
    }
#endif

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
