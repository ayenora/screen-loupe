import SwiftUI

/// The Background list beside the palette: the screen, a few
/// colours and a colour of one's own, calm gradients, an image, and whether a One Window picture
/// keeps the window's shadow. Shown in `StudioListPanel`, as the Size list is.
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
            StudioListRow(title: "Screen", isChecked: current == .screen) { choose(.screen) }
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
            .padding(.horizontal, StudioListLook.contentInset)
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
            .padding(.horizontal, StudioListLook.contentInset)
            Divider().padding(.vertical, 4)
            StudioListRow(title: imageTitle, isChecked: isImage, action: chooseImage)
            Divider().padding(.vertical, 4)
            StudioListRow(title: "Window Shadow", isChecked: windowShadow, action: toggleWindowShadow)
        }
        .padding(StudioListLook.padding)
        .frame(width: StudioListLook.width)
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
        StudioListLook.header(hovered.flatMap { names.contains($0) ? "\(title) · \($0)" : nil } ?? title)
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
