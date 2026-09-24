import AppKit

@main
@MainActor
enum ScreenLoupeApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        // `NSApplication.delegate` is weak; `run()` doesn't return until the app quits.
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
