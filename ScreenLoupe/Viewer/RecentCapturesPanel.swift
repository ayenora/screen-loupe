import AppKit
import SwiftUI

/// The Recent Captures panel at the right of the Viewer (docs/product.md, Recent Captures): the
/// live view on top, which can't be deleted, with Take Snapshot beside it, then one row per capture,
/// newest first — thumbnail, "Snapshot" or the image file's name, its size and time, and Delete.
/// Clicking a row shows it in the Viewer. Every size is multiplied by `captures.scale`, so the panel grows with the
/// column.
struct RecentCapturesPanel: View {
    let captures: RecentCaptures

    var body: some View {
        let s = captures.scale
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent Captures").font(.system(size: 13 * s, weight: .bold))
                Spacer()
                Text("\(captures.captures.count) of \(RecentCaptures.limit)")
                    .font(.system(size: 11 * s).monospacedDigit())
                    .foregroundStyle(.secondary)
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
            Text("Last \(RecentCaptures.limit) snapshots and images · kept until quit")
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
            Image(systemName: "viewfinder")
                .font(.system(size: 20 * s, weight: .regular))
                .foregroundStyle(isShown ? Color.accentColor : .secondary)
                .frame(width: 76 * s, height: 50 * s)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4 * s))
                .overlay(RoundedRectangle(cornerRadius: 4 * s).strokeBorder(Color(nsColor: .separatorColor)))
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

/// Take Snapshot: keeps what the live view shows as a new row, whatever the Viewer shows. A
/// borderless button with the standard hover and pressed look, its symbol at the toolbar's size; off
/// without a frame to take.
private struct SnapshotButton: View {
    let captures: RecentCaptures

    private var s: CGFloat { captures.scale }

    var body: some View {
        Button {
            captures.onTakeSnapshot?()
        } label: {
            Image(systemName: "camera")
                .font(.system(size: 13 * s))
        }
        .buttonStyle(.accessoryBar)
        .controlSize(.large)
        .disabled(!captures.canTakeSnapshot)
        .help("Take Snapshot")
        .accessibilityLabel("Take Snapshot")
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
                Text(capture.details)
                    .font(.system(size: 11 * s).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
        .accessibilityAddTraits(isShown ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: "Show") { captures.show(capture.id) }
    }

    private var thumbnail: some View {
        Group {
            if let image = capture.thumbnail {
                // A tiny kept crop is magnified, so its pixels stay sharp as in the Viewer; a larger
                // one is scaled down smoothly.
                let fit = min(76 * s / CGFloat(image.width), 50 * s / CGFloat(image.height)) * displayScale
                Image(decorative: image, scale: 1).resizable().interpolation(fit > 1 ? .none : .medium)
                    .scaledToFit()
            } else {
                Color.secondary.opacity(0.2)
            }
        }
        .frame(width: 76 * s, height: 50 * s)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 4 * s))
        .overlay(RoundedRectangle(cornerRadius: 4 * s).strokeBorder(Color(nsColor: .separatorColor)))
    }
}
