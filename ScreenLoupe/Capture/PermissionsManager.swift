import AppKit
import CoreGraphics

/// Screen Recording permission (TASK.md §14).
@MainActor
final class PermissionsManager {
    /// Whether the app may capture the screen. macOS may keep reporting `false` after the user
    /// grants access until the app is relaunched.
    var hasScreenRecordingAccess: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Shows the system prompt the first time; later calls return at once without a prompt.
    @discardableResult
    func requestScreenRecordingAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Starts a fresh instance of the app and quits this one, so a new grant takes effect.
    func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}
