import CoreGraphics

/// The window levels of the app's floating windows, as raw window-server levels (`NSWindow.Level`
/// takes them as its raw value): the frames and overlays at the status window's level, the window
/// picker's panels above them, and the Screenshot studio's palette above everything, so its buttons
/// stay reachable over the frames, the picker, a Viewer kept on top and other apps' windows, also
/// in a full-screen app's Space. Menus stay above it.
enum WindowLevels {
    /// The Capture Area's and the studio's frames and their overlays (`NSWindow.Level.statusBar`).
    static let frames = Int(CGWindowLevelForKey(.statusWindow))
    /// The window picker's panels: above the frames, so a click on a frame picks the window under it.
    static let picker = frames + 1
    /// The studio's palette, and what it opens beside itself: its hover label and its lists.
    static let studioPalette = picker + 1
}
