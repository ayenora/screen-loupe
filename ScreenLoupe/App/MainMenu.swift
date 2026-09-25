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
        let help = helpMenu(target: target)
        menu.addItem(submenuItem(help))
        NSApp.helpMenu = help
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
    /// The standard items go to the first responder, so text fields cut, copy and paste as usual:
    /// ⌘C is `copy(_:)`, which a text field with the focus takes, and `AppController`, the app
    /// delegate, turns into Copy View otherwise.
    private static func editMenu(target: AppController) -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.delegate = target
        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy View", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        let copySource = menu.addItem(
            withTitle: "Copy Source", action: #selector(AppController.copySource(_:)), keyEquivalent: "C")
        copySource.target = target
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        return menu
    }

    private static func viewMenu(target: AppController) -> NSMenu {
        let menu = NSMenu(title: "View")
        let reset = menu.addItem(
            withTitle: "Reset Zoom", action: #selector(AppController.resetZoom(_:)), keyEquivalent: "0")
        reset.target = target
        let sizeToArea = menu.addItem(
            withTitle: "Size Window to Area", action: #selector(AppController.sizeViewerToArea(_:)),
            keyEquivalent: "0")
        sizeToArea.keyEquivalentModifierMask = [.command, .option]
        sizeToArea.target = target
        // Space in the Viewer also freezes; a bare-Space key equivalent would steal it from text fields.
        let freeze = menu.addItem(
            withTitle: "Freeze Frame", action: #selector(AppController.toggleFreeze(_:)), keyEquivalent: "")
        freeze.target = target
        let later = NSMenu(title: "Freeze Later")
        for seconds in [3, 5, 10] {
            let item = later.addItem(
                withTitle: "Freeze in \(seconds) Seconds", action: #selector(AppController.freezeAfterDelay(_:)),
                keyEquivalent: "")
            item.tag = seconds
            item.target = target
        }
        let laterItem = submenuItem(later)
        laterItem.title = later.title
        menu.addItem(laterItem)
        let select = menu.addItem(
            withTitle: "Select", action: #selector(AppController.toggleSelectTool(_:)), keyEquivalent: "e")
        select.target = target
        let ruler = menu.addItem(
            withTitle: "Ruler", action: #selector(AppController.toggleMeasuringRuler(_:)), keyEquivalent: "r")
        ruler.target = target
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
        let pick = menu.addItem(
            withTitle: "Fit Capture Area to Window…", action: #selector(AppController.pickWindowForCaptureArea(_:)),
            keyEquivalent: "")
        pick.target = target
        let onTop = menu.addItem(
            withTitle: "Keep Viewer on Top", action: #selector(AppController.toggleViewerAlwaysOnTop(_:)),
            keyEquivalent: "")
        onTop.target = target
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        return menu
    }

    /// The guide lives on the project's website (docs/guide.md).
    private static func helpMenu(target: AppController) -> NSMenu {
        let menu = NSMenu(title: "Help")
        let guide = menu.addItem(
            withTitle: "Screen Loupe Guide", action: #selector(AppController.showGuide(_:)), keyEquivalent: "?")
        guide.target = target
        let shortcuts = menu.addItem(
            withTitle: "Keyboard Shortcuts", action: #selector(AppController.showKeyboardShortcuts(_:)),
            keyEquivalent: "")
        shortcuts.target = target
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
