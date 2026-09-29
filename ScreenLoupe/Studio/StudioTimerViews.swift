import AppKit
import SwiftUI

/// The Timer list beside the palette: how long Capture, Copy
/// and Save wait. Shown in `StudioListPanel`, as the Size list is.
struct StudioTimerList: View {
    let current: StudioDelay
    let choose: (StudioDelay) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(StudioDelay.allCases, id: \.self) { delay in
                StudioListRow(title: delay.title, isChecked: delay == current) { choose(delay) }
            }
        }
        .padding(StudioListLook.padding)
        .frame(width: 120)
    }
}

/// The studio's countdown beside its frame's tab: `CountdownPill` in the studio's orange.
///
/// A click-through panel that never becomes key, so the pointer and the keyboard stay with the app
/// the user works in. It is the app's window, so neither a picture nor the Viewer shows it.
@MainActor
final class StudioCountdownPanel: NSPanel {
    private let pillView = CountdownPillView()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = NSWindow.Level(rawValue: WindowLevels.frames)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        contentView = pillView
    }

    override var canBecomeKey: Bool { false }

    /// The size `text` needs.
    func size(for text: String) -> CGSize { CountdownPill.studio.size(for: text) }

    /// Shows `text`, `seconds` in the ring and `fraction` of the ring left, in `rect` (AppKit global
    /// points), above the frame.
    func show(_ text: String, seconds: Int, fraction: CGFloat, in rect: CGRect) {
        pillView.content = (text, seconds, fraction)
        if frame != rect { setFrame(rect, display: false) }
        if !isVisible { orderFrontRegardless() }
    }
}

private final class CountdownPillView: NSView {
    var content = ("", 0, CGFloat(0)) {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        CountdownPill.studio.draw(content.0, seconds: content.1, fraction: content.2, in: bounds)
    }
}
