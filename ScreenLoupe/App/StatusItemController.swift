import AppKit

/// The menu bar item (docs/product.md, Menu bar and app mode). The app keeps running from here when the Viewer is closed.
@MainActor
final class StatusItemController {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    init(target: AppController) {
        item.button?.image = NSImage(systemSymbolName: "plus.magnifyingglass", accessibilityDescription: "Screen Loupe")

        let menu = NSMenu()
        menu.addItem(Self.item("Show Viewer", #selector(AppController.showViewer(_:)), target))
        menu.addItem(Self.item("Show Capture Area", #selector(AppController.toggleCaptureArea(_:)), target))
        menu.addItem(
            Self.item("Fit Capture Area to Window…", #selector(AppController.pickWindowForCaptureArea(_:)), target))
        menu.addItem(Self.item("Keep Viewer on Top", #selector(AppController.toggleViewerAlwaysOnTop(_:)), target))
        menu.addItem(.separator())
        menu.addItem(Self.item("Copy View", #selector(AppController.copyView(_:)), target))
        menu.addItem(Self.item("Copy Source", #selector(AppController.copySource(_:)), target))
        menu.addItem(Self.item("Reset Zoom", #selector(AppController.resetZoom(_:)), target))
        menu.addItem(.separator())
        menu.addItem(Self.item("Settings…", #selector(AppController.showSettings(_:)), target))
        // Menu bar only, the app has no Help menu: the guide is reached from here.
        menu.addItem(Self.item("Screen Loupe Guide", #selector(AppController.showGuide(_:)), target))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Screen Loupe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        item.menu = menu
    }

    private static func item(_ title: String, _ action: Selector, _ target: AnyObject) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        return item
    }
}
