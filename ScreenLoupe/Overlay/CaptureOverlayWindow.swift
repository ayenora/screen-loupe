import AppKit

/// The borderless, transparent panel that carries the Capture Area frame above every other window.
///
/// Clicks on fully transparent pixels — the inside of the frame — pass through to the app underneath.
/// Only the drawn parts (the line, and on hover the band, handles and tab) take the mouse.
final class CaptureOverlayWindow: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: WindowLevels.frames)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isMovable = false
        acceptsMouseMovedEvents = true
        // Key only for a press whose view needs it (`CaptureOverlayView.needsPanelToBecomeKey`): not
        // for the viewport handle, which leaves the keyboard with the app underneath.
        becomesKeyOnlyIfNeeded = true
    }

    /// Borderless windows can't become key by default; the frame needs it for arrow-key nudges.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
