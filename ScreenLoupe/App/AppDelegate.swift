import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = AppController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.willTerminate()
    }

    /// Closing the Viewer keeps the app running in the menu bar (docs/product.md, Menu bar and app mode).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller.reopen()
        return true
    }

    /// Edit › Copy View (⌘C) when no text field has the focus: the app delegate ends the responder
    /// chain, so a text field with the focus copies its text first.
    @objc func copy(_ sender: Any?) {
        controller.copyView(sender)
    }
}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        controller.validateMenuItem(menuItem)
    }
}
