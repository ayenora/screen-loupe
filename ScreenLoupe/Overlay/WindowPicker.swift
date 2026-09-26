import AppKit

/// Picks a window for the Capture Area to take or to attach to, like Space in ⇧⌘4: the window under
/// the pointer is tinted, a click takes it, Escape or a click on no window cancels (docs/product.md,
/// Capture Area).
///
/// A transparent panel over each display takes every click, so none reaches the app underneath and
/// no Accessibility permission is needed.
@MainActor
final class WindowPicker {
    /// The windows that can be picked, front to back.
    private let windows: [ScreenWindow]
    private let tint: NSColor
    /// What a click does, shown on the tinted window.
    private let hint: String
    private let onFinish: (ScreenWindow?) -> Void
    private var panels: [PickerPanel] = []
    private var observer: NSObjectProtocol?

    /// `onFinish` gets the picked window, or `nil` when picking was cancelled.
    init(windows: [ScreenWindow], tint: NSColor, hint: String, onFinish: @escaping (ScreenWindow?) -> Void) {
        self.windows = windows
        self.tint = tint
        self.hint = hint
        self.onFinish = onFinish
    }

    func start() {
        NSApp.activate()
        for screen in NSScreen.screens {
            let panel = PickerPanel(frame: screen.frame)
            let view = PickerView(tint: tint, hint: hint)
            view.picker = self
            panel.contentView = view
            panel.orderFrontRegardless()
            panels.append(panel)
        }
        let mouse = NSEvent.mouseLocation
        (panels.first { $0.frame.contains(mouse) } ?? panels.first)?.makeKey()
        mouseMoved()
        // Switching to another app leaves no panel behind to swallow its clicks.
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish(nil) }
        }
    }

    fileprivate func mouseMoved() {
        let hovered = WindowMagnet.window(at: NSEvent.mouseLocation, in: windows)
        for panel in panels {
            (panel.contentView as? PickerView)?.show(
                hovered.map { $0.frame.offsetBy(dx: -panel.frame.minX, dy: -panel.frame.minY) })
        }
    }

    fileprivate func click() {
        finish(WindowMagnet.window(at: NSEvent.mouseLocation, in: windows))
    }

    fileprivate func finish(_ picked: ScreenWindow?) {
        guard !panels.isEmpty else { return }
        observer.map(NotificationCenter.default.removeObserver)
        observer = nil
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        onFinish(picked)
    }
}

private final class PickerPanel: NSPanel {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Above the Capture Area frame, so a click on the frame picks the window under it too.
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        // Set explicitly, a transparent window takes the clicks on its transparent pixels too.
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Tints the hovered window's part of one display, with a hint in the middle.
private final class PickerView: NSView {
    weak var picker: WindowPicker?
    private let tint: NSColor
    private let hint: String
    private var hovered: CGRect?

    init(tint: NSColor, hint: String) {
        self.tint = tint
        self.hint = hint
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(_ rect: CGRect?) {
        guard rect != hovered else { return }
        hovered = rect
        needsDisplay = true
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(
            NSTrackingArea(
                rect: .zero, options: [.mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect], owner: self))
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }
    override func mouseMoved(with event: NSEvent) { picker?.mouseMoved() }
    override func mouseDown(with event: NSEvent) { picker?.click() }
    override func rightMouseDown(with event: NSEvent) { picker?.finish(nil) }
    override func cancelOperation(_ sender: Any?) { picker?.finish(nil) }

    override func draw(_ dirtyRect: NSRect) {
        guard let hovered else { return }
        tint.withAlphaComponent(0.22).setFill()
        hovered.fill()
        let outline = NSBezierPath(rect: hovered.insetBy(dx: 1, dy: 1))
        outline.lineWidth = 2
        tint.setStroke()
        outline.stroke()

        let text = hint as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: OverlayStyle.tabFont, .foregroundColor: NSColor.white]
        let size = text.size(withAttributes: attributes)
        let pill = CGRect(
            x: (hovered.midX - size.width / 2 - 10).rounded(), y: (hovered.midY - 12).rounded(),
            width: (size.width + 20).rounded(.up), height: 24)
        OverlayStyle.labelFill.setFill()
        NSBezierPath(roundedRect: pill, xRadius: 12, yRadius: 12).fill()
        text.draw(at: CGPoint(x: pill.minX + 10, y: pill.midY - size.height / 2), withAttributes: attributes)
    }
}
