import AppKit

/// The main menu, built in code: the app has no nib or storyboard.
@MainActor
enum MainMenu {
    static func make(target: AppController) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(submenuItem(appMenu(target: target)))
        menu.addItem(submenuItem(fileMenu(target: target)))
        menu.addItem(submenuItem(editMenu(target: target)))
        menu.addItem(submenuItem(viewMenu(target: target)))
        let window = windowMenu(target: target)
        menu.addItem(submenuItem(window))
        NSApp.windowsMenu = window
        #if DEBUG
            menu.addItem(submenuItem(debugMenu(target: target)))
        #endif
        return menu
    }

    private static func appMenu(target: AppController) -> NSMenu {
        let name = ProcessInfo.processInfo.processName
        let menu = NSMenu(title: name)
        menu.addItem(
            withTitle: "About \(name)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: "")
        menu.addItem(.separator())
        let settings = menu.addItem(
            withTitle: "Settings…", action: #selector(AppController.showSettings(_:)), keyEquivalent: ",")
        settings.target = target
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

    private static func fileMenu(target: AppController) -> NSMenu {
        let menu = NSMenu(title: "File")
        let saveView = menu.addItem(
            withTitle: "Save View…", action: #selector(AppController.saveView(_:)), keyEquivalent: "s")
        saveView.target = target
        let saveSource = menu.addItem(
            withTitle: "Save Source…", action: #selector(AppController.saveSource(_:)), keyEquivalent: "S")
        saveSource.target = target
        menu.addItem(.separator())
        menu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        return menu
    }

    /// ⌘C copies what the Viewer shows; ⇧⌘C the Capture Area without zoom (docs/product.md, Screenshots).
    private static func editMenu(target: AppController) -> NSMenu {
        let menu = NSMenu(title: "Edit")
        let copyView = menu.addItem(
            withTitle: "Copy View", action: #selector(AppController.copyView(_:)), keyEquivalent: "c")
        copyView.target = target
        let copySource = menu.addItem(
            withTitle: "Copy Source", action: #selector(AppController.copySource(_:)), keyEquivalent: "C")
        copySource.target = target
        return menu
    }

    private static func viewMenu(target: AppController) -> NSMenu {
        let menu = NSMenu(title: "View")
        let reset = menu.addItem(
            withTitle: "Reset Zoom", action: #selector(AppController.resetZoom(_:)), keyEquivalent: "0")
        reset.target = target
        menu.addItem(.separator())
        // AppKit retitles this item "Exit Full Screen" on its own while the window is full screen.
        let fullScreen = menu.addItem(
            withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]
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
        let onTop = menu.addItem(
            withTitle: "Keep Viewer on Top", action: #selector(AppController.toggleViewerAlwaysOnTop(_:)),
            keyEquivalent: "")
        onTop.target = target
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        return menu
    }

    #if DEBUG
        /// Only in Debug builds: states that are hard to reach by hand.
        private static func debugMenu(target: AppController) -> NSMenu {
            let menu = NSMenu(title: "Debug")
            let recovers = menu.addItem(
                withTitle: "Simulate Interruption (Recovers)",
                action: #selector(AppController.simulateInterruptionThatRecovers(_:)), keyEquivalent: "")
            recovers.target = target
            let fails = menu.addItem(
                withTitle: "Simulate Interruption (Fails)",
                action: #selector(AppController.simulateInterruptionThatFails(_:)), keyEquivalent: "")
            fails.target = target
            return menu
        }
    #endif

    private static func submenuItem(_ submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem()
        item.submenu = submenu
        return item
    }
}
