import Foundation

struct CaptureTimeoutError: LocalizedError {
    var errorDescription: String? { "The screen capture service didn't respond." }
}

/// Runs `operation`, giving up with `CaptureTimeoutError` after `seconds`.
///
/// ScreenCaptureKit's async calls can't be cancelled, and when the connection to the capture service
/// drops ("application connection being interrupted") a call in flight may never return. Without a
/// timeout that one call would block every later update. On a timeout the call is left running in the
/// background and its eventual result is ignored.
func withTimeout<T>(seconds: Double, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    let gate = ResumeGate()
    let box = try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<UncheckedBox<T>, any Error>) in
        Task {
            do {
                let value = try await operation()
                if gate.claim() { continuation.resume(returning: UncheckedBox(value: value)) }
            } catch {
                if gate.claim() { continuation.resume(throwing: error) }
            }
        }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if gate.claim() { continuation.resume(throwing: CaptureTimeoutError()) }
        }
    }
    return box.value
}

/// Lets exactly one of the racing tasks resume the continuation.
private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.withLock {
            defer { claimed = true }
            return !claimed
        }
    }
}

/// Carries a ScreenCaptureKit result (not `Sendable`) out of the racing task. The value is handed
/// over once and only read by the caller.
private struct UncheckedBox<T>: @unchecked Sendable {
    let value: T
}
