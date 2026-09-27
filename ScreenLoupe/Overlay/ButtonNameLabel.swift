import AppKit

/// Names the button under the pointer in a small label beside it, as the system's tooltips do:
/// after a rest on the button, or at once while the pointer goes on from a named button
/// (`HoverLabelDelay`). AppKit shows tooltips only while the app is active, which the studio
/// palette and the frames, non-activating panels, don't make it, so they name their buttons with
/// this. The label is a child window of `parent`, at its level, and takes no mouse.
@MainActor
final class ButtonNameLabel {
    private let panel = ButtonNamePanel()
    private weak var parent: NSWindow?
    private var timer: Timer?
    /// The button the pointer last entered, until it leaves it or clicks.
    private var hovered: AnyHashable?
    /// The hovered button's name and where its label goes, until it leaves it or clicks.
    private var pending: (name: String, frame: (CGSize) -> CGRect?)?
    /// When a shown name last went as the pointer left its button; `nil` after a click and while
    /// the buttons are hidden.
    private var hiddenAt: TimeInterval?

    init(parent: NSWindow) {
        self.parent = parent
    }

    /// The pointer entered `button`: `name` shows after the rest, where `frame` puts a label of the
    /// size it is given, in AppKit global coordinates; `nil` shows none.
    func pointerEntered(_ button: AnyHashable, name: String, frame: @escaping (CGSize) -> CGRect?) {
        hide()
        hovered = button
        pending = (name, frame)
        let delay = HoverLabelDelay.delay(at: ProcessInfo.processInfo.systemUptime, lastHidden: hiddenAt)
        guard delay > 0 else {
            show()
            return
        }
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.show() }
        }
    }

    /// An exit from a button the pointer has already left for another changes nothing: where
    /// buttons touch, the next one's enter can come first.
    func pointerExited(_ button: AnyHashable) {
        guard hovered == button else { return }
        hovered = nil
        pending = nil
        hide()
    }

    /// A click or hiding: the name goes, and the next button waits the full rest.
    func end() {
        hovered = nil
        pending = nil
        hide()
        hiddenAt = nil
    }

    private func hide() {
        timer?.invalidate()
        timer = nil
        guard panel.isVisible else { return }
        parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        hiddenAt = ProcessInfo.processInfo.systemUptime
    }

    private func show() {
        timer = nil
        guard let (name, frame) = pending else { return }
        let size = CGSize(width: OverlayStyle.labelWidth(for: name), height: OverlayMetrics.standard.labelHeight)
        guard let parent, parent.isVisible, let rect = frame(size) else { return }
        panel.level = parent.level
        panel.show(name, in: rect)
        parent.addChildWindow(panel, ordered: .above)
    }
}

/// The name of the hovered button: a small label in the look of the frame's at-rest size label.
private final class ButtonNamePanel: NSPanel {
    private let label = SizeLabelView()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        contentView = label
    }

    func show(_ text: String, in rect: CGRect) {
        label.text = text
        setFrame(rect, display: true)
    }
}
