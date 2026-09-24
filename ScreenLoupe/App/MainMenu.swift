import AppKit

/// The main menu, built in code: the app has no nib or storyboard.
@MainActor
enum MainMenu {
    static func make(target: AppController) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(submenuItem(appMenu()))
        let window = windowMenu(target: target)
        menu.addItem(submenuItem(window))
        NSApp.windowsMenu = window
        return menu
    }

    private static func appMenu() -> NSMenu {
        let name = ProcessInfo.processInfo.processName
        let menu = NSMenu(title: name)
        menu.addItem(
            withTitle: "About \(name)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Hide \(name)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = menu.addItem(
            withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(
            withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit \(name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private static func windowMenu(target: AppController) -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        let viewer = menu.addItem(
            withTitle: "Show Viewer", action: #selector(AppController.showViewer(_:)), keyEquivalent: "")
        viewer.target = target
        let area = menu.addItem(
            withTitle: "Show Capture Area", action: #selector(AppController.toggleCaptureArea(_:)), keyEquivalent: "")
        area.target = target
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        return menu
    }

    private static func submenuItem(_ submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem()
        item.submenu = submenu
        return item
    }
}
