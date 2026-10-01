import AppKit
import SwiftUI

/// The Recent Captures panel at the right of the Viewer: Paste and Add… in the header, the
/// live view on top, which can't be deleted, with Take Snapshot beside it, then one row per capture,
/// newest first — square thumbnail, "Snapshot" or the image file's name, its size, its date and time,
/// Link View and Delete. Clicking a row shows it in the Viewer; its context menu uses it as a
/// reference. Every size but the camera button's is multiplied by `captures.scale`, so the panel
/// grows with the column.
struct RecentCapturesPanel: View {
    let captures: RecentCaptures

    var body: some View {
        let s = captures.scale
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Recent Captures").font(.system(size: 13 * s, weight: .bold))
                Spacer()
                PanelButton(title: "Paste", scale: s) { captures.onPaste?() }
                PanelButton(title: "Add…", scale: s) { captures.onOpenImage?() }
            }
            .padding(.horizontal, 14 * s)
            .padding(.top, 12 * s)
            .padding(.bottom, 8 * s)

            HStack(spacing: 6 * s) {
                LiveRow(captures: captures)
                SnapshotButton(captures: captures)
            }
            .padding(.horizontal, 8 * s)
            .padding(.bottom, 8 * s)
            Divider()
                .padding(.bottom, 6 * s)

            if captures.captures.isEmpty {
                Text(
                    "Take a snapshot of the Capture Area — the camera or ⌘T — or open an image file, and the picture waits here to be studied later."
                )
                .font(.system(size: 12 * s))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14 * s)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 4 * s) {
                        ForEach(captures.captures) { capture in
                            CaptureRow(captures: captures, capture: capture)
                        }
                    }
                    .padding(.horizontal, 8 * s)
                }
            }

            Divider()
            Text("\(captures.captures.count) of \(RecentCaptures.limit) · kept until deleted")
                .font(.system(size: 10.5 * s))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14 * s)
                .padding(.vertical, 7 * s)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// The live view: what the Capture Area shows now, with its size in pixels while there is a frame.
/// Chosen whenever no capture shows.
private struct LiveRow: View {
    let captures: RecentCaptures

    private var s: CGFloat { captures.scale }
    private var isShown: Bool { captures.shownID == nil }

    var body: some View {
        HStack(spacing: 10 * s) {
            // Square, as a capture's thumbnail, so the size text has the width.
            Image(systemName: "viewfinder")
                .font(.system(size: 20 * s, weight: .regular))
                .foregroundStyle(isShown ? Color.accentColor : .secondary)
                .thumbnailTile(scale: s)
            VStack(alignment: .leading, spacing: 2 * s) {
                Text("Live").font(.system(size: 12 * s, weight: .semibold))
                if let size = captures.liveSize {
                    Text(RecentCaptureRules.sizeText(size))
                        .font(.system(size: 11 * s).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(6 * s)
        .background(RoundedRectangle(cornerRadius: 8 * s).fill(isShown ? Color.accentColor.opacity(0.15) : .clear))
        .overlay(
            RoundedRectangle(cornerRadius: 8 * s).strokeBorder(isShown ? Color.accentColor : .clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture { captures.show(nil) }
        .accessibilityAddTraits(isShown ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: "Show") { captures.show(nil) }
    }
}

/// Take Snapshot: keeps what the live view shows as a new row, whatever the Viewer shows. A Viewer
/// toolbar button, not scaled with the panel as the toolbar isn't; off without a frame to take.
private struct SnapshotButton: View {
    let captures: RecentCaptures

    var body: some View {
        Button {
            captures.onTakeSnapshot?()
        } label: {
            Image(systemName: "camera")
        }
        .buttonStyle(ToolbarButtonStyle())
        .disabled(!captures.canTakeSnapshot)
        .help("Take Snapshot")
        .accessibilityLabel("Take Snapshot")
    }
}

/// A Viewer toolbar button (`ToolbarLook`): `buttonSize`, the symbol at the `.large` scale of the
/// 13 pt default in `labelColor`, no fill at rest, a `systemFill` circle while pressed (from macOS 26,
/// where the button is square; before, a rect with the toolbar's fill corners), and a tertiary
/// symbol when off.
private struct ToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration)
    }

    private struct Content: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let look = ToolbarLook.current
            let shape = RoundedRectangle(cornerRadius: look.fillRadius ?? look.buttonSize.height / 2)
            configuration.label
                .font(.system(size: 13))
                .imageScale(.large)
                .foregroundStyle(Color(nsColor: isEnabled ? .labelColor : .tertiaryLabelColor))
                .frame(width: look.buttonSize.width, height: look.buttonSize.height)
                .background(shape.fill(configuration.isPressed ? Color(nsColor: .systemFill) : .clear))
                .contentShape(shape)
        }
    }
}

private struct CaptureRow: View {
    let captures: RecentCaptures
    let capture: RecentCapture

    private var s: CGFloat { captures.scale }
    private var isShown: Bool { captures.shownID == capture.id }
    private static let accent = Color(nsColor: .systemPurple)
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        HStack(spacing: 10 * s) {
            thumbnail
            VStack(alignment: .leading, spacing: 2 * s) {
                Text(capture.name).font(.system(size: 12 * s, weight: .semibold)).lineLimit(1)
                    .truncationMode(.middle)
                Group {
                    Text(capture.sizeText)
                    Text(capture.dateText)
                }
                .font(.system(size: 11 * s).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            LinkToggle(captures: captures, capture: capture)
            Button {
                captures.remove(capture.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11 * s, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20 * s, height: 20 * s)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Delete")
            .accessibilityLabel("Delete capture")
        }
        .padding(6 * s)
        .background(
            RoundedRectangle(cornerRadius: 8 * s).fill(isShown ? Self.accent.opacity(0.18) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8 * s).strokeBorder(isShown ? Self.accent : .clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture { captures.show(capture.id) }
        .contextMenu {
            Button("Use as Reference") { captures.onUseAsReference?(capture) }
                .disabled(!canUseAsReference)
        }
        // One element, with Show, Link or Unlink View, Use as Reference and Delete as its actions.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(capture.name), \(capture.sizeText), \(capture.dateText)\(linkState)")
        .accessibilityAddTraits(isShown ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { captures.show(capture.id) }
        .accessibilityAction(named: "Show") { captures.show(capture.id) }
        .accessibilityActions {
            if capture.isLinked {
                Button("Unlink view") { captures.setLinked(capture.id, false) }
            } else if captures.canLink(capture) {
                Button("Link view") { captures.setLinked(capture.id, true) }
            }
            if canUseAsReference {
                Button("Use as reference") { captures.onUseAsReference?(capture) }
            }
        }
        .accessibilityAction(named: "Delete capture") { captures.remove(capture.id) }
    }

    /// Whether the references take another layer: off at their limit, as Add… is.
    private var canUseAsReference: Bool { captures.canUseAsReference?() == true }

    /// Whether it is linked, or why it can't be: its tooltip isn't read, as the row is one element.
    private var linkState: String {
        if capture.isLinked { return ", linked" }
        return captures.canLink(capture) ? "" : ", sizes differ from linked"
    }

    private var thumbnail: some View {
        Group {
            if let image = capture.thumbnail {
                // A tiny kept crop is magnified, so its pixels stay sharp as in the Viewer; a larger
                // one is scaled down smoothly.
                let fit = RecentCaptures.thumbnailSide * s / CGFloat(max(image.width, image.height)) * displayScale
                Image(decorative: image, scale: 1).resizable().interpolation(fit > 1 ? .none : .medium)
                    .scaledToFit()
            } else {
                Color.secondary.opacity(0.2)
            }
        }
        .thumbnailTile(scale: s)
    }
}

/// Links a capture's view with the other linked ones, left of Delete: a bare link glyph when off, white
/// on a system blue square when on, and tertiary when the picture's size differs from the linked
/// ones' — then a click does nothing and the tooltip says why. Not `.disabled`, which would hide the
/// tooltip.
private struct LinkToggle: View {
    let captures: RecentCaptures
    let capture: RecentCapture

    private var s: CGFloat { captures.scale }

    var body: some View {
        let canLink = captures.canLink(capture)
        Button {
            if canLink { captures.setLinked(capture.id, !capture.isLinked) }
        } label: {
            Image(systemName: "link")
                .font(.system(size: 11 * s, weight: .semibold))
                .foregroundStyle(
                    capture.isLinked
                        ? Color.white : Color(nsColor: canLink ? .secondaryLabelColor : .tertiaryLabelColor)
                )
                .frame(width: 20 * s, height: 20 * s)
                .background(
                    RoundedRectangle(cornerRadius: 5 * s).fill(capture.isLinked ? Color(nsColor: .systemBlue) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help(canLink: canLink))
    }

    private func help(canLink: Bool) -> String {
        if capture.isLinked { return "Unlink View" }
        if canLink { return "Link View" }
        let linked = captures.linkedSize.map(RecentCaptureRules.sizeText) ?? ""
        return "Sizes differ: this is \(capture.sizeText), linked are \(linked)"
    }
}

extension View {
    /// A row's square tile, a capture's thumbnail or the Live row's placeholder:
    /// `RecentCaptures.thumbnailSide` at `scale`, on a faint fill with a hairline border.
    fileprivate func thumbnailTile(scale s: CGFloat) -> some View {
        frame(width: RecentCaptures.thumbnailSide * s, height: RecentCaptures.thumbnailSide * s)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 4 * s))
            .overlay(RoundedRectangle(cornerRadius: 4 * s).strokeBorder(Color(nsColor: .separatorColor)))
    }
}
