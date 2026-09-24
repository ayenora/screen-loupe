import AppKit

extension DisplayLayout {
    /// The current arrangement of `NSScreen.screens`. `nil` only if no screen is connected.
    @MainActor
    static func current() -> DisplayLayout? {
        DisplayLayout(displays: NSScreen.screens.compactMap(DisplayInfo.init(screen:)))
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
