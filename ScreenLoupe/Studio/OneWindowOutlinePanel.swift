import AppKit

/// The green outline around the window One Window captures, with its app's name (`OneWindowOutline`): click-through,
/// never key, not in ⌘Tab or the Window
/// menu, at the frames' level so it shows over the window. It is the app's window, so no capture
/// and not the Viewer shows it.
@MainActor
final class OneWindowOutlinePanel: NSPanel {
    /// The app's green preset, apart from the studio's orange and the Capture Area's colour.
    static let color = SettingsColor.green

    private let lineView = OutlineLineView()
    private let label = SizeLabelView()
    private var shown: (outline: OneWindowOutline, text: String, screen: CGRect)?

    /// The app's name where it shows, with the visible frame it is kept on, in AppKit global
    /// coordinates: One Window's notice and countdown sit beside it. `nil` while hidden.
    var labelPlace: (label: CGRect, screen: CGRect)? {
        guard isVisible, let shown else { return nil }
        return (shown.outline.label, shown.screen)
    }

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
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        let content = NSView()
        content.addSubview(lineView)
        content.addSubview(label)
        contentView = content
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Outlines a window at `window`, in AppKit global coordinates, named `appName`, with a line of
    /// `lineWidth` points, the label kept on `screen`. Moves only when something changed.
    func show(around window: CGRect, appName: String, lineWidth: CGFloat, screen: CGRect) {
        let labelSize = CGSize(
            width: OverlayStyle.labelWidth(for: appName), height: OverlayMetrics.standard.labelHeight)
        let outline = OneWindowOutline(window: window, lineWidth: lineWidth, labelSize: labelSize, screen: screen)
        if shown?.outline != outline || shown?.text != appName {
            shown = (outline, appName, screen)
            setFrame(outline.panel, display: false)
            let origin = outline.panel.origin
            lineView.frame = CGRect(origin: .zero, size: outline.panel.size)
            lineView.line = outline.line.offsetBy(dx: -origin.x, dy: -origin.y)
            lineView.lineWidth = lineWidth
            label.frame = outline.label.offsetBy(dx: -origin.x, dy: -origin.y)
            label.text = appName
        }
        if !isVisible { orderFrontRegardless() }
    }

    func hide() {
        orderOut(nil)
        shown = nil
    }
}

/// The line in the green, with the frame's halo outside it.
private final class OutlineLineView: NSView {
    /// The line's outer edge; the line is drawn inside it, the halo outside.
    var line: CGRect = .zero { didSet { needsDisplay = true } }
    var lineWidth: CGFloat = 1 { didSet { needsDisplay = true } }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let haloWidth = OverlayMetrics.standard.haloWidth
        let halo = NSBezierPath(rect: line.insetBy(dx: -haloWidth / 2, dy: -haloWidth / 2))
        halo.lineWidth = haloWidth
        OverlayStyle.halo(for: effectiveAppearance).setStroke()
        halo.stroke()
        let path = NSBezierPath(rect: line.insetBy(dx: lineWidth / 2, dy: lineWidth / 2))
        path.lineWidth = lineWidth
        OneWindowOutlinePanel.color.nsColor.setStroke()
        path.stroke()
    }
}

/// One Window's notice, beside the chosen window's name or the palette while the studio's frame,
/// beside whose tab notices go, is hidden: what was copied or saved, or why a picture was refused or
/// failed. Drawn as the frame's notice (`SizeLabelView`), it stays `OverlayStyle.noticeDelay`, then
/// fades as the frame's does; shown again while it fades, it comes back at once. Click-through,
/// never key, at the palette's level, so the window picker's panels never cover it while a window
/// is picked; the app's window, so no picture shows it.
@MainActor
final class StudioNoticePanel: NSPanel {
    private let label = SizeLabelView()
    private var timer: Timer?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = NSWindow.Level(rawValue: WindowLevels.studioPalette)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        label.wantsLayer = true
        contentView = label
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// The text shown, while it shows.
    var text: String? { isVisible ? label.text : nil }

    /// The size `text` needs.
    static func size(for text: String) -> CGSize {
        CGSize(width: OverlayStyle.labelWidth(for: text), height: OverlayMetrics.standard.labelHeight)
    }

    /// Shows `text` in `rect` (AppKit global points) at once, also over one fading, and fades it
    /// after the notice's delay.
    func show(_ text: String, in rect: CGRect) {
        label.text = text
        move(to: rect)
        // A fade still running would end at zero over the new notice.
        label.layer?.removeAllAnimations()
        label.alphaValue = 1
        if !isVisible { orderFrontRegardless() }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: OverlayStyle.noticeDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fadeOut() }
        }
    }

    /// Follows what it sits beside.
    func move(to rect: CGRect) {
        if frame != rect { setFrame(rect, display: true) }
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        label.layer?.removeAllAnimations()
        orderOut(nil)
    }

    private func fadeOut() {
        timer = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = OverlayStyle.noticeFadeDuration
            label.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // Shown again meanwhile: it stays.
                guard let self, self.timer == nil else { return }
                self.orderOut(nil)
            }
        }
    }
}
