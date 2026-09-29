import AppKit

/// Hands the system colour panel's colour, as the user changes it, to `onChange`, through a colour
/// well of its own that is never shown. The panel is shared with the colour wells in Settings, so
/// its target and action are left alone: activating this well exclusively deactivates any other
/// well before the panel takes this well's colour, and another well activating, or the panel
/// closing, deactivates this one. A colour chosen for the frame never becomes the background, nor
/// the other way round.
@MainActor
final class ColorPanelTarget: NSObject {
    var onChange: ((NSColor) -> Void)?
    private let well = NSColorWell(frame: .zero)
    private var closeObserver: NSObjectProtocol?

    override init() {
        super.init()
        well.target = self
        well.action = #selector(colorChanged(_:))
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: NSColorPanel.shared, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.well.deactivate() }
        }
    }

    /// The panel is bound to `onChange`: shown by `show(from:)`, and not closed nor taken by another
    /// well since.
    var isActive: Bool { well.isActive }

    /// Binds the panel to `onChange`, starting from `color` when there is one, and shows it.
    func show(from color: NSColor?) {
        if let color { well.color = color }
        well.activate(true)
        NSColorPanel.shared.makeKeyAndOrderFront(nil)
    }

    @objc private func colorChanged(_ sender: NSColorWell) {
        onChange?(sender.color)
    }
}
