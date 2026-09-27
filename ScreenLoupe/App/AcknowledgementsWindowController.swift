import AppKit

/// Help › Acknowledgements: the third-party notices from `Acknowledgements.txt`, read-only and selectable.
@MainActor
final class AcknowledgementsWindowController: NSWindowController {
    init() {
        let scroll = NSTextView.scrollableTextView()
        let text = scroll.documentView as! NSTextView
        text.isEditable = false
        text.textContainerInset = NSSize(width: 12, height: 12)
        let url = Bundle.main.url(forResource: "Acknowledgements", withExtension: "txt")!
        text.string = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        // Set after the text, so they apply to all of it.
        text.font = .systemFont(ofSize: NSFont.systemFontSize)
        text.textColor = .labelColor

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Acknowledgements"
        window.contentView = scroll
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Brings the window forward, above the Viewer when the Viewer is kept on top.
    func show(above level: NSWindow.Level) {
        window?.level = level
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
