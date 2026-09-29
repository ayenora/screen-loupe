import AppKit
import SwiftUI

/// The Background list beside the palette (docs/product.md, Screenshot studio): the screen, a few
/// colours and a colour of one's own, calm gradients, an image, and whether a One Window picture
/// keeps the window's shadow. Shown in `StudioListPanel`, as
/// the Size list is.
struct StudioBackgroundList: View {
    let current: StudioBackground
    let choose: (StudioBackground) -> Void
    let chooseCustomColor: () -> Void
    let chooseImage: () -> Void
    let windowShadow: Bool
    let toggleWindowShadow: () -> Void
    /// The swatch under the pointer, named in its section's header: tooltips don't show while
    /// another app is active.
    @State private var hovered: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SizeRow(title: "Screen", isChecked: current == .screen) { choose(.screen) }
            header("Color", naming: StudioBackground.colors.map(\.name) + ["Custom Color…"])
            HStack(spacing: 8) {
                ForEach(StudioBackground.colors.indices, id: \.self) { index in
                    let entry = StudioBackground.colors[index]
                    Swatch(name: entry.name, isChecked: current == .color(entry.color), hovered: $hovered) {
                        choose(.color(entry.color))
                    } fill: {
                        Color(entry.color)
                    }
                }
                Swatch(
                    name: "Custom Color…", isChecked: current.isCustomColor, hovered: $hovered,
                    action: chooseCustomColor
                ) {
                    AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center)
                }
            }
            .padding(.horizontal, 8)
            header("Gradient", naming: StudioBackground.gradients.map(\.name))
            HStack(spacing: 8) {
                ForEach(StudioBackground.gradients.indices, id: \.self) { index in
                    let entry = StudioBackground.gradients[index]
                    Swatch(name: entry.name, isChecked: current == .gradient(entry.gradient), hovered: $hovered) {
                        choose(.gradient(entry.gradient))
                    } fill: {
                        LinearGradient(
                            colors: [Color(entry.gradient.top), Color(entry.gradient.bottom)], startPoint: .top,
                            endPoint: .bottom)
                    }
                }
            }
            .padding(.horizontal, 8)
            Divider().padding(.vertical, 4)
            SizeRow(title: imageTitle, isChecked: isImage, action: chooseImage)
            Divider().padding(.vertical, 4)
            SizeRow(title: "Window Shadow", isChecked: windowShadow, action: toggleWindowShadow)
        }
        .padding(6)
        .frame(width: 240)
    }

    private var isImage: Bool {
        if case .image = current { return true }
        return false
    }

    /// `Image…`, or `Image… · Beach.heic` while one is chosen.
    private var imageTitle: String {
        if case .image(let image) = current { return "Image… · \(image.name)" }
        return "Image…"
    }

    /// `Color`, or `Color · White` while the pointer is on one of `names`.
    private func header(_ title: String, naming names: [String]) -> some View {
        Text(hovered.flatMap { names.contains($0) ? "\(title) · \($0)" : nil } ?? title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }
}

/// A square of colour, ringed in the accent while it is the background.
private struct Swatch<Fill: View>: View {
    let name: String
    let isChecked: Bool
    @Binding var hovered: String?
    let action: () -> Void
    @ViewBuilder let fill: () -> Fill

    private var isHovered: Bool { hovered == name }

    var body: some View {
        Button(action: action) {
            fill()
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.separator))
                .padding(2)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(
                            isChecked ? Color.accentColor : isHovered ? Color.secondary : .clear, lineWidth: 2)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside {
                hovered = name
            } else if hovered == name {
                hovered = nil
            }
        }
        .help(name)
        .accessibilityLabel(name)
    }
}

extension Color {
    init(_ color: BackgroundColor) {
        self.init(.sRGB, red: color.red, green: color.green, blue: color.blue)
    }
}

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
