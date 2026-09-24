/// Carries a value that isn't `Sendable` (a ScreenCaptureKit result, a `CGImage`, a Metal texture)
/// across an isolation boundary. Use only where the value is handed over once and nothing mutates it
/// on both sides.
struct UncheckedSendable<T>: @unchecked Sendable {
    let value: T
}
