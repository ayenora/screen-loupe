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

    /// The color space frames captured from display `id` come in, sRGB when unknown.
    static func colorSpace(forDisplay id: CGDirectDisplayID?) -> CGColorSpace {
        id.flatMap { screen(forDisplay: $0) }?.colorSpace?.cgColorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
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

extension ViewerFrame {
    /// The colour space the pixels are in: the one kept with them (an opened image's own, a recent
    /// capture's), else the display's they come from.
    var colorSpace: CGColorSpace {
        imageColorSpace ?? NSScreen.colorSpace(forDisplay: displayID)
    }

    /// The name of that colour space for the Color Meter, such as "Display P3" or an image's
    /// profile; `nil` when the system has none (`ColorSample` then names it).
    var colorSpaceName: String? {
        if let imageColorSpace { return NSColorSpace(cgColorSpace: imageColorSpace)?.localizedName }
        return displayID.flatMap { NSScreen.screen(forDisplay: $0) }?.colorSpace?.localizedName
    }
}
