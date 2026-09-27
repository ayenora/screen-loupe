import AppKit
import SwiftUI

/// A row of the Size list or the Background list, highlighted under the pointer as a menu item is.
struct SizeRow: View {
    let title: String
    let isChecked: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .opacity(isChecked ? 1 : 0)
                    .frame(width: 12)
                Text(title)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .foregroundStyle(isHovered ? Color.white : Color.primary)
            .background(RoundedRectangle(cornerRadius: 4).fill(isHovered ? Color.accentColor : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// The Size list or the Background list beside the palette: a non-activating panel in the
/// pop-over's look. A click on an entry works without activating the app; a click in a text field
/// makes only this panel key, so typing reaches it while the app the user works in stays active
/// and none of this app's other windows come forward. Closed by an entry, Escape, the button that
/// opened it, a drag of the palette, hiding the studio, or a click outside it and the palette.
@MainActor
final class StudioListPanel: NSPanel {
    /// Called whenever the list is ordered out, by any of the ways that close it.
    var onClose: (() -> Void)?
    private var monitors: [Any] = []

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    }

    /// Key only for its text fields (`becomesKeyOnlyIfNeeded`).
    override var canBecomeKey: Bool { true }

    /// Escape while a field has the focus.
    override func cancelOperation(_ sender: Any?) { dismiss() }

    /// Shows `list` at `origin(size)`, a child of `palette` so it stays beside it; clicks outside
    /// both close it.
    func show<List: View>(_ list: List, beside palette: NSWindow, origin: (CGSize) -> CGPoint) {
        let host = FirstMouseHostingView(rootView: list)
        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.maskImage = StudioPalette.roundedMask(radius: 10)
        host.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            host.topAnchor.constraint(equalTo: background.topAnchor),
            host.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        contentView = background
        let size = host.fittingSize
        setFrame(CGRect(origin: origin(size), size: size), display: true)
        // At the palette's level, above every other window as it is.
        level = palette.level
        palette.addChildWindow(self, ordered: .above)
        orderFront(nil)
        startMonitoring(besides: palette)
    }

    /// Also when hidden some other way: the monitors never outlive the list.
    func dismiss() {
        guard !monitors.isEmpty || parent != nil else { return }
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        parent?.removeChildWindow(self)
        orderOut(nil)
    }

    override func orderOut(_ sender: Any?) {
        super.orderOut(sender)
        onClose?()
    }

    /// A press in another app, or in a window of this app other than the panel and the palette,
    /// closes it. Presses on the palette are left to its buttons: Size toggles the list.
    private func startMonitoring(besides palette: NSWindow) {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let monitor = NSEvent.addGlobalMonitorForEvents(
            matching: mask, handler: { [weak self] _ in MainActor.assumeIsolated { self?.dismiss() } })
        {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: mask,
            handler: { [weak self, weak palette] event in
                MainActor.assumeIsolated {
                    if let self, event.window !== self, event.window !== palette { self.dismiss() }
                }
                return event
            })
        {
            monitors.append(monitor)
        }
    }
}

/// Takes the first click, so a size is chosen with one click while another app is active.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
