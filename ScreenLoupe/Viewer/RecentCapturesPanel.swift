import AppKit
import SwiftUI

/// The Recent Captures panel at the right of the Viewer (docs/product.md, Recent Captures): one row
/// per capture, newest first — thumbnail, what was copied, its size and time, and Delete. Clicking a
/// row shows that capture in the Viewer. Every size is multiplied by `captures.scale`, so the panel
/// grows with the column.
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

            if captures.captures.isEmpty {
                Text(
                    "Copy or save in the Viewer — ⌘C, ⇧⌘C, ⌘S, an Option-drag or a selection — and the picture waits here to be studied later."
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
            Text("Last \(RecentCaptures.limit) copies and saves · kept until quit")
                .font(.system(size: 10.5 * s))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14 * s)
                .padding(.vertical, 7 * s)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct CaptureRow: View {
    let captures: RecentCaptures
    let capture: RecentCapture

    private var s: CGFloat { captures.scale }
    private var isShown: Bool { captures.shownID == capture.id }
    private static let accent = Color(nsColor: .systemPurple)

    var body: some View {
        HStack(spacing: 10 * s) {
            thumbnail
            VStack(alignment: .leading, spacing: 2 * s) {
                Text(capture.kind).font(.system(size: 12 * s, weight: .semibold)).lineLimit(1)
                Text("\(capture.imageSize.width) × \(capture.imageSize.height) px · \(capture.time)")
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
                Image(decorative: image, scale: 1).resizable().interpolation(.medium).scaledToFit()
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
