import AppKit
import SwiftUI

/// A row of swatches in the palette's Background menu, one menu item for a section's colours or
/// gradients, like Finder's row of tag colours: each a square of its colour or gradient, the
/// background ringed in the accent, the one under the pointer ringed in grey and named in the
/// section's header, as `Color · White` (tooltips don't show while another app is active). A click
/// chooses it and closes the menu. Greyed and taking no clicks while One Window is on. Each swatch
/// is a button named for assistive apps; the menu's arrow keys pass over the row, whose choices are
/// also in Screenshot › Background.
struct StudioSwatchRow: View {
    let entries: [(name: String, background: StudioBackground)]
    let current: StudioBackground
    let isEnabled: Bool
    /// The hovered swatch's name, or `nil`: the header shows it.
    let hover: (String?) -> Void
    let choose: (StudioBackground) -> Void
    @State private var hovered: String?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(entries.indices, id: \.self) { index in
                let entry = entries[index]
                Swatch(name: entry.name, isChecked: current == entry.background, hovered: $hovered) {
                    choose(entry.background)
                } fill: {
                    switch entry.background {
                    case .color(let color): AnyView(Color(color))
                    case .gradient(let gradient):
                        AnyView(
                            LinearGradient(
                                colors: [Color(gradient.top), Color(gradient.bottom)], startPoint: .top,
                                endPoint: .bottom))
                    case .screen, .image: AnyView(Color.clear)
                    }
                }
            }
        }
        .padding(.horizontal, Self.inset)
        .padding(.vertical, 3)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .onChange(of: hovered) { _, name in hover(name) }
    }

    /// Left of the first swatch: where a menu item's title starts, past the checkmark column.
    private static let inset: CGFloat = 14

    /// The row as a menu item's view, `header` the section's header item, named `Title · Name`
    /// while a swatch is hovered. A click closes the menu first, then chooses.
    @MainActor static func view(
        entries: [(name: String, background: StudioBackground)], current: StudioBackground, isEnabled: Bool,
        header: NSMenuItem, choose: @escaping (StudioBackground) -> Void
    ) -> NSView {
        let title = header.title
        weak var hosting: NSHostingView<StudioSwatchRow>?
        let row = StudioSwatchRow(
            entries: entries, current: current, isEnabled: isEnabled,
            hover: { name in header.title = name.map { "\(title) · \($0)" } ?? title },
            choose: { background in
                hosting?.enclosingMenuItem?.menu?.cancelTracking()
                choose(background)
            })
        let view = NSHostingView(rootView: row)
        hosting = view
        view.frame = CGRect(origin: .zero, size: view.fittingSize)
        return view
    }
}

/// A swatch's size and corners, and its ring's width just outside it.
private enum SwatchLook {
    static let side: CGFloat = 26
    static let radius: CGFloat = 5
    static let ring: CGFloat = 2
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
                .frame(width: SwatchLook.side, height: SwatchLook.side)
                .clipShape(RoundedRectangle(cornerRadius: SwatchLook.radius))
                .overlay(RoundedRectangle(cornerRadius: SwatchLook.radius).strokeBorder(.separator))
                .padding(SwatchLook.ring)
                .overlay(
                    // Around the swatch, its corners concentric with the swatch's.
                    RoundedRectangle(cornerRadius: SwatchLook.radius + SwatchLook.ring)
                        .strokeBorder(
                            isChecked ? Color.accentColor : isHovered ? Color.secondary : .clear,
                            lineWidth: SwatchLook.ring)
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
