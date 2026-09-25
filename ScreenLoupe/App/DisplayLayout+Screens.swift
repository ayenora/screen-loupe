import AppKit

extension DisplayLayout {
    /// The current arrangement of `NSScreen.screens`. `nil` only if no screen is connected.
    @MainActor
    static func current() -> DisplayLayout? {
        DisplayLayout(displays: NSScreen.screens.compactMap(DisplayInfo.init(screen:)))
    }
}

extension NSScreen {
    /// The screen of a `CGDirectDisplayID`, if it is still connected.
    static func screen(forDisplay id: CGDirectDisplayID) -> NSScreen? {
        screens.first { DisplayInfo(screen: $0)?.id == id }
    }

    /// The other app whose full-screen Space shows on this screen now. macOS has no public API for
    /// Spaces; the sign, read from the windows on screen: no Dock window over the display (it is on
    /// every ordinary Space), the normal-level windows all belong to one other app, and one of them
    /// spans the display's width down to its bottom (an app may leave the menu bar's strip at the
    /// top free). Reading windows' bounds and owners needs no permission.
    var otherAppInFullScreen: NSRunningApplication? {
        guard let id = DisplayInfo(screen: self)?.id,
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return nil }
        let display = CGDisplayBounds(id)
        let own = ProcessInfo.processInfo.processIdentifier
        var owners = Set<pid_t>()
        var spans = false
        for window in windows {
            guard let owner = window[kCGWindowOwnerPID as String] as? pid_t, owner != own,
                let rect = (window[kCGWindowBounds as String] as? NSDictionary)
                    .flatMap({ CGRect(dictionaryRepresentation: $0 as CFDictionary) }),
                rect.intersects(display)
            else { continue }
            if window[kCGWindowOwnerName as String] as? String == "Dock", rect == display { return nil }
            guard (window[kCGWindowLayer as String] as? Int) == 0 else { continue }
            owners.insert(owner)
            if rect.minX == display.minX, rect.width == display.width, rect.maxY == display.maxY { spans = true }
        }
        guard spans, owners.count == 1, let owner = owners.first else { return nil }
        return NSRunningApplication(processIdentifier: owner)
    }

    /// The color space frames captured from display `id` come in, sRGB when unknown.
    static func colorSpace(forDisplay id: CGDirectDisplayID) -> CGColorSpace {
        screen(forDisplay: id)?.colorSpace?.cgColorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
    }
}

extension DisplayInfo {
    init?(screen: NSScreen) {
        // `NSScreen.CGDirectDisplayID` exists only from macOS 26; this key works everywhere.
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        self.init(id: number.uint32Value, globalFrame: screen.frame, scale: screen.backingScaleFactor)
    }
}
