import AppKit
import SwiftUI

/// The Settings window: an AppKit window with the standard toolbar tabs, each tab a SwiftUI form.
/// Every change applies at once; there is no Save button.
@MainActor
final class SettingsWindowController: NSWindowController {
    init(settings: SettingsStore, shortcuts: GlobalShortcuts) {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        func add(_ title: String, symbol: String, _ view: some View) {
            let host = NSHostingController(rootView: view)
            host.sizingOptions = .preferredContentSize
            let item = NSTabViewItem(viewController: host)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            tabs.addTabViewItem(item)
        }
        add("General", symbol: "gearshape", GeneralSettingsView(store: settings))
        add("Capture Area", symbol: "viewfinder", CaptureAreaSettingsView(store: settings))
        add("Viewer", symbol: "plus.magnifyingglass", ViewerSettingsView(store: settings))
        add("Screenshots", symbol: "camera", ScreenshotSettingsView(store: settings))
        add("Shortcuts", symbol: "keyboard", ShortcutSettingsView(store: settings, shortcuts: shortcuts))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.center()
        window.setFrameAutosaveName("Settings")
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Brings the window forward, above the Viewer when the Viewer is kept on top.
    func show(above level: NSWindow.Level) {
        window?.level = level
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
