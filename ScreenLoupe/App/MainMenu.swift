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
        menu.addItem(submenuItem(screenshotMenu(target: target)))
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
        let open = menu.addItem(
            withTitle: "Open Image…", action: #selector(AppController.openImage(_:)), keyEquivalent: "o")
        open.target = target
        menu.addItem(.separator())
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

    /// ⌘C copies what the Viewer shows; ⇧⌘C the Capture Area without zoom.
    /// The standard items go to the first responder, so text fields cut, copy and paste as usual:
    /// ⌘C is `copy(_:)`, which a text field with the focus takes, and `AppController`, the app
    /// delegate, turns into Copy View otherwise; ⌘V, `paste(_:)`, likewise pastes an image into the
    /// Viewer (Dropping and pasting images).
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
        let pasteAsReference = menu.addItem(
            withTitle: "Paste as Reference", action: #selector(AppController.pasteAsReference(_:)), keyEquivalent: "")
        pasteAsReference.target = target
        let pasteForInspection = menu.addItem(
            withTitle: "Paste for Inspection", action: #selector(AppController.pasteForInspection(_:)),
            keyEquivalent: "")
        pasteForInspection.target = target
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
        menu.addItem(submenuItem(later))
        let snapshot = menu.addItem(
            withTitle: "Take Snapshot", action: #selector(AppController.takeSnapshot(_:)), keyEquivalent: "t")
        snapshot.target = target
        let select = menu.addItem(
            withTitle: "Select", action: #selector(AppController.toggleSelectTool(_:)), keyEquivalent: "e")
        select.target = target
        let ruler = menu.addItem(
            withTitle: "Ruler", action: #selector(AppController.toggleMeasuringRuler(_:)), keyEquivalent: "r")
        ruler.target = target
        let viewportHandle = menu.addItem(
            withTitle: "Show Viewport Handle", action: #selector(AppController.toggleViewportHandle(_:)),
            keyEquivalent: "")
        viewportHandle.target = target
        menu.addItem(.separator())
        // AppKit retitles this item "Exit Full Screen" on its own while the window is full screen.
        let fullScreen = menu.addItem(
            withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]
        return menu
    }

    /// The Screenshot studio: everything its palette does, so it
    /// works with the palette out of reach.
    private static func screenshotMenu(target: AppController) -> NSMenu {
        let menu = NSMenu(title: "Screenshot")
        let studio = menu.addItem(
            withTitle: "Show Screenshot Studio", action: #selector(AppController.toggleScreenshotStudio(_:)),
            keyEquivalent: "")
        studio.target = target
        menu.addItem(.separator())
        let capture = menu.addItem(
            withTitle: "Capture", action: #selector(AppController.captureStudio(_:)), keyEquivalent: "")
        capture.target = target
        let copy = menu.addItem(withTitle: "Copy", action: #selector(AppController.copyStudio(_:)), keyEquivalent: "")
        copy.target = target
        let save = menu.addItem(withTitle: "Save…", action: #selector(AppController.saveStudio(_:)), keyEquivalent: "")
        save.target = target
        menu.addItem(.separator())
        // Filled each time it opens: the custom sizes change.
        let sizes = NSMenu(title: "Size")
        sizes.identifier = studioSizeMenu
        sizes.delegate = target
        menu.addItem(submenuItem(sizes))
        let fit = menu.addItem(
            withTitle: "Fit to Window…", action: #selector(AppController.fitStudioToWindow(_:)), keyEquivalent: "")
        fit.target = target
        let aspectLock = menu.addItem(
            withTitle: "Lock Aspect Ratio", action: #selector(AppController.toggleStudioAspectLock(_:)),
            keyEquivalent: "")
        aspectLock.target = target
        let delays = NSMenu(title: "Delay")
        for delay in StudioDelay.allCases {
            let item = delays.addItem(
                withTitle: delay.title, action: #selector(AppController.chooseStudioDelay(_:)), keyEquivalent: "")
            item.tag = delay.rawValue
            item.target = target
        }
        menu.addItem(submenuItem(delays))
        let output = outputMenu(target: target)
        menu.addItem(submenuItem(output))
        menu.addItem(.separator())
        let background = backgroundMenu(target: target)
        menu.addItem(submenuItem(background))
        // Retitled Stop One Window while a window is chosen.
        let oneWindow = menu.addItem(
            withTitle: "Capture One Window…", action: #selector(AppController.toggleStudioOneWindow(_:)),
            keyEquivalent: "")
        oneWindow.target = target
        let pointer = menu.addItem(
            withTitle: "Include the Pointer", action: #selector(AppController.toggleStudioPointer(_:)),
            keyEquivalent: "")
        pointer.target = target
        return menu
    }

    /// Screenshot › Output: how studio pictures are written. Each item carries its choice;
    /// `validateMenuItem` checks the current ones.
    private static func outputMenu(target: AppController) -> NSMenu {
        let menu = NSMenu(title: "Output")
        func add(_ header: String, _ choices: [(title: String, value: Any)], action: Selector) {
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            menu.addItem(.sectionHeader(title: header))
            for choice in choices {
                let item = menu.addItem(withTitle: choice.title, action: action, keyEquivalent: "")
                item.representedObject = choice.value
                item.target = target
            }
        }
        add(
            "Format", StudioOutput.Format.allCases.map { ($0.title, $0) },
            action: #selector(AppController.chooseStudioFormat(_:)))
        add(
            "Color", StudioOutput.Colors.allCases.map { ($0.title, $0) },
            action: #selector(AppController.chooseStudioColors(_:)))
        add(
            "Scale", StudioOutput.Scale.allCases.map { ($0.title, $0) },
            action: #selector(AppController.chooseStudioScale(_:)))
        return menu
    }

    /// Screenshot › Background: the same choices as the palette's Background list. Each fixed
    /// choice carries its `StudioBackground`; `validateMenuItem` checks the current one.
    private static func backgroundMenu(target: AppController) -> NSMenu {
        let menu = NSMenu(title: "Background")
        func add(_ title: String, _ background: StudioBackground) {
            let item = menu.addItem(
                withTitle: title, action: #selector(AppController.chooseStudioBackground(_:)), keyEquivalent: "")
            item.representedObject = background
            item.target = target
        }
        add("Screen", .screen)
        menu.addItem(.sectionHeader(title: "Color"))
        for entry in StudioBackground.colors { add(entry.name, .color(entry.color)) }
        let custom = menu.addItem(
            withTitle: "Custom Color…", action: #selector(AppController.chooseStudioCustomColor(_:)), keyEquivalent: "")
        custom.target = target
        menu.addItem(.sectionHeader(title: "Gradient"))
        for entry in StudioBackground.gradients { add(entry.name, .gradient(entry.gradient)) }
        menu.addItem(.separator())
        let image = menu.addItem(
            withTitle: "Image…", action: #selector(AppController.chooseStudioBackgroundImage(_:)), keyEquivalent: "")
        image.target = target
        menu.addItem(.separator())
        let shadow = menu.addItem(
            withTitle: "Window Shadow", action: #selector(AppController.toggleStudioWindowShadow(_:)), keyEquivalent: ""
        )
        shadow.target = target
        return menu
    }

    static let studioSizeMenu = NSUserInterfaceItemIdentifier("studioSize")

    /// Screenshot › Size: the presets, the custom sizes in slot order, and Custom Size…. Each size
    /// item carries `[width, height]` in pixels, and a custom one tag 1; `validateMenuItem` checks
    /// the frame's size (`StudioSizes.isChecked`).
    static func fillStudioSizeMenu(_ menu: NSMenu, custom: [CustomSize], target: AppController) {
        menu.removeAllItems()
        func add(_ header: String, _ sizes: [(size: PixelSize, title: String)], isCustom: Bool = false) {
            menu.addItem(.sectionHeader(title: header))
            for entry in sizes {
                let item = menu.addItem(
                    withTitle: entry.title, action: #selector(AppController.applyStudioSize(_:)), keyEquivalent: "")
                item.representedObject = [entry.size.width, entry.size.height]
                item.tag = isCustom ? 1 : 0
                item.target = target
            }
        }
        add("Mac App Store", StudioSizes.appStore.map { ($0, StudioSizes.title($0)) })
        add("Web", StudioSizes.web.map { ($0, StudioSizes.title($0)) })
        if !custom.isEmpty {
            add("Custom", custom.map { ($0.pixels, StudioSizes.title($0)) }, isCustom: true)
        }
        menu.addItem(.separator())
        let edit = menu.addItem(
            withTitle: "Custom Size…", action: #selector(AppController.showStudioCustomSizes(_:)), keyEquivalent: "")
        edit.target = target
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
        let margins = menu.addItem(
            withTitle: "Capture Area Margins", action: #selector(AppController.toggleCaptureAreaMargins(_:)),
            keyEquivalent: "")
        margins.target = target
        let resetArea = menu.addItem(
            withTitle: "Reset Capture Area", action: #selector(AppController.resetCaptureArea(_:)), keyEquivalent: "")
        resetArea.target = target
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
        menu.addItem(.separator())
        let acknowledgements = menu.addItem(
            withTitle: "Acknowledgements", action: #selector(AppController.showAcknowledgements(_:)),
            keyEquivalent: "")
        acknowledgements.target = target
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

    /// An item that opens `submenu`, titled as it is.
    private static func submenuItem(_ submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem()
        item.title = submenu.title
        item.submenu = submenu
        return item
    }
}
