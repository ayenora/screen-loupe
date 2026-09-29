import AppKit

/// The Screenshot studio's backdrop (`StudioBackdrop`): a
/// borderless window over a whole display, just above the desktop icons, showing the chosen
/// background as one picture at the display's pixels. Click-through, never key, not in ⌘Tab or
/// the Window menu, on every Space and still in Mission Control, like the desktop it covers.
@MainActor
final class StudioBackdropWindow: NSWindow {
    private let backdropView = BackdropView()

    init() {
        // Not deferred: the window number is there from the start, for the capture filters.
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: WindowLevels.studioBackdrop)
        ignoresMouseEvents = true
        isOpaque = true
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        contentView = backdropView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Shows `image`, the whole of the display at `frame`, there, behind every window.
    func show(_ image: CGImage, over frame: CGRect) {
        backdropView.image = image
        setFrame(frame, display: false)
        orderFrontRegardless()
    }

    /// The picture is let go with the window, so a large one isn't held while nothing shows.
    func hide() {
        orderOut(nil)
        backdropView.image = nil
    }
}

/// The backdrop's picture as its layer's contents: the display's pixels one to one.
private final class BackdropView: NSView {
    var image: CGImage? {
        didSet {
            needsDisplay = true
            // A hidden window isn't drawn, so `updateLayer` wouldn't let the picture go.
            if image == nil { layer?.contents = nil }
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.contents = image
        layer.contentsGravity = .resize
        // One image pixel to one display pixel; while a new picture for a changed scale is on its
        // way, the old one is stretched without blending.
        layer.magnificationFilter = .nearest
        layer.minificationFilter = .nearest
    }
}

/// Waits for refreshes of a screen with its display link, so the window server has shown what was
/// committed before (`StudioController.backdropOnScreen`). A display that doesn't refresh — asleep,
/// or gone meanwhile — ends the wait after a quarter second, so a picture is never held up for good.
@MainActor
final class ScreenRefresh: NSObject {
    private var remaining: Int
    private var continuation: CheckedContinuation<Void, Never>?
    private var link: CADisplayLink?
    /// The longest wait, for a display that doesn't refresh.
    private static let longestWait: TimeInterval = 0.25

    private init(_ count: Int) {
        remaining = count
    }

    /// Returns after `count` refreshes of `screen`, or `longestWait` at most.
    static func wait(_ count: Int, on screen: NSScreen) async {
        let waiter = ScreenRefresh(count)
        await withCheckedContinuation { continuation in
            waiter.continuation = continuation
            // The link and the timer hold the waiter until it finishes.
            let link = screen.displayLink(target: waiter, selector: #selector(refreshed))
            waiter.link = link
            link.add(to: .main, forMode: .common)
            let timer = Timer(timeInterval: longestWait, repeats: false) { _ in
                MainActor.assumeIsolated { waiter.finish() }
            }
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    @objc private func refreshed() {
        remaining -= 1
        if remaining <= 0 { finish() }
    }

    private func finish() {
        link?.invalidate()
        link = nil
        continuation?.resume()
        continuation = nil
    }
}
