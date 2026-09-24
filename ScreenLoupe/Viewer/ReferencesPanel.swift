import AppKit
import SwiftUI

/// The References panel at the right of the Viewer (docs/product.md, References): the layers, top
/// first, one row each like layers in an image editor, and below them the settings of the selected
/// layer. A row drags as a whole to reorder; the settings never drag anything.
///
/// Every size is multiplied by `references.scale`, so the panel grows with the column. The slider
/// and the blend switch are drawn here rather than taken from AppKit, so they scale too.
struct ReferencesPanel: View {
    let references: ReferencesController
    let window: () -> NSWindow?

    var body: some View {
        let s = references.scale
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("References").font(.system(size: 13 * s, weight: .bold))
                Spacer()
                PanelButton(title: "Add…", scale: s) { references.addFromFiles(in: window()) }
                    .disabled(references.layers.count >= ReferenceStack.limit)
            }
            .padding(.horizontal, 14 * s)
            .padding(.top, 12 * s)
            .padding(.bottom, 8 * s)

            if references.layers.isEmpty {
                Text("Add an image — a design export or a screenshot — to lay it over the live pixels.")
                    .font(.system(size: 12 * s))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14 * s)
                Spacer()
            } else {
                List(selection: selection) {
                    ForEach(references.layers) { layer in
                        LayerRow(references: references, layer: layer)
                            .tag(layer.id)
                            .listRowInsets(EdgeInsets(top: 0, leading: 6 * s, bottom: 0, trailing: 6 * s))
                    }
                    // The whole row lifts and moves; the others make room.
                    .onMove { offsets, destination in
                        references.update { $0.move(fromOffsets: offsets, toOffset: destination) }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 30 * s)

                if let layer = references.layers.first(where: { $0.id == references.selectedID }) {
                    LayerProperties(references: references, layer: layer)
                }
            }

            Divider()
            Text("\(references.layers.count) of \(ReferenceStack.limit) · drag a row to reorder · top is on top")
                .font(.system(size: 10.5 * s))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14 * s)
                .padding(.vertical, 7 * s)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var selection: Binding<UUID?> {
        Binding(get: { references.selectedID }, set: { references.select($0) })
    }
}

// MARK: - A layer's row

private struct LayerRow: View {
    let references: ReferencesController
    let layer: ReferenceLayer

    private var s: CGFloat { references.scale }
    private var isSelected: Bool { references.selectedID == layer.id }

    var body: some View {
        HStack(spacing: 6 * s) {
            Grip(scale: s)
            IconButton(
                symbol: layer.isVisible ? "eye" : "eye.slash", label: layer.isVisible ? "Hide" : "Show", scale: s
            ) {
                references.update(layer.id) { $0.isVisible.toggle() }
            }
            Thumbnail(image: references.image(for: layer), scale: s)
                .opacity(layer.isVisible ? 1 : 0.4)
            Text(layer.name)
                .font(.system(size: 12 * s, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.middle)
                .opacity(layer.isVisible ? 1 : 0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(Int((layer.opacity * 100).rounded()))%")
                .font(.system(size: 11 * s).monospacedDigit())
                .foregroundStyle(.secondary)
            IconButton(
                symbol: layer.isPinned ? "pin.fill" : "pin",
                label: layer.isPinned
                    ? "Unpin: drag it in the Viewer again" : "Pin: the mouse in the Viewer passes it by",
                scale: s, tint: layer.isPinned ? .accentColor : nil
            ) {
                references.update(layer.id) { $0.isPinned.toggle() }
            }
        }
        .frame(height: 30 * s)
        .contentShape(Rectangle())
    }
}

// MARK: - The selected layer's settings

private struct LayerProperties: View {
    let references: ReferencesController
    let layer: ReferenceLayer

    private var s: CGFloat { references.scale }

    var body: some View {
        VStack(alignment: .leading, spacing: 8 * s) {
            HStack(spacing: 6 * s) {
                Text("LAYER")
                    .font(.system(size: 10.5 * s, weight: .bold))
                    .kerning(0.4 * s)
                    .foregroundStyle(.secondary)
                Text(layer.name)
                    .font(.system(size: 12 * s, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                IconButton(symbol: "trash", label: "Delete", scale: s) { references.remove(layer.id) }
            }
            HStack(spacing: 8 * s) {
                ScrubLabel(title: "Opacity", value: opacityPercent, step: 1, scale: s)
                ScaledSlider(value: binding(\.opacity), scale: s)
                Text("\(Int((layer.opacity * 100).rounded()))%")
                    .font(.system(size: 11 * s).monospacedDigit())
                    .frame(width: 32 * s, alignment: .trailing)
            }
            BlendSwitch(selection: binding(\.blend), scale: s)
            Grid(alignment: .leading, horizontalSpacing: 8 * s, verticalSpacing: 8 * s) {
                GridRow {
                    ScrubField(title: "X", value: pointBinding(\.x), step: 1, unit: "px", scale: s)
                    ScrubField(title: "Y", value: pointBinding(\.y), step: 1, unit: "px", scale: s)
                }
                GridRow {
                    ScrubField(title: "Scale", value: scaleBinding, step: 1, unit: "%", scale: s)
                    HStack {
                        Spacer()
                        IconButton(symbol: "arrow.counterclockwise", label: "Reset position and scale", scale: s) {
                            references.update(layer.id) {
                                $0.origin = .zero
                                $0.scale = 1
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 10 * s)
        .padding(.vertical, 10 * s)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .top) { Divider() }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<ReferenceLayer, Value>) -> Binding<Value> {
        Binding(
            get: { layer[keyPath: keyPath] },
            set: { value in references.update(layer.id) { $0[keyPath: keyPath] = value } })
    }

    private var opacityPercent: Binding<Double> {
        Binding(
            get: { layer.opacity * 100 },
            set: { value in references.update(layer.id) { $0.opacity = min(max(value / 100, 0), 1) } })
    }

    /// The top-left corner in whole source pixels from the Capture Area's top-left.
    private func pointBinding(_ keyPath: WritableKeyPath<CGPoint, CGFloat>) -> Binding<Double> {
        Binding(
            get: { Double(layer.origin[keyPath: keyPath]) },
            set: { value in references.update(layer.id) { $0.origin[keyPath: keyPath] = CGFloat(value.rounded()) } })
    }

    private var scaleBinding: Binding<Double> {
        Binding(
            get: { Double(layer.scale * 100) },
            set: { value in
                let scale = min(
                    max(CGFloat(value) / 100, ReferenceStack.scaleRange.lowerBound),
                    ReferenceStack.scaleRange.upperBound)
                references.update(layer.id) { $0.scale = scale }
            })
    }
}

// MARK: - Controls that scale

/// ⠿: the row drags to reorder.
private struct Grip: View {
    let scale: CGFloat

    var body: some View {
        Canvas { context, size in
            let dot = 2.4 * scale
            for column in 0..<2 {
                for row in 0..<3 {
                    let rect = CGRect(
                        x: CGFloat(column) * 4 * scale + 1 * scale, y: CGFloat(row) * 4 * scale + 1 * scale,
                        width: dot, height: dot)
                    context.fill(Path(ellipseIn: rect), with: .color(.secondary))
                }
            }
        }
        .frame(width: 10 * scale, height: 14 * scale)
        .accessibilityHidden(true)
    }
}

private struct IconButton: View {
    let symbol: String
    let label: String
    let scale: CGFloat
    var tint: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12 * scale, weight: .medium))
                .foregroundStyle(tint ?? .secondary)
                .frame(width: 18 * scale, height: 18 * scale)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct PanelButton: View {
    let title: String
    let scale: CGFloat
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11 * scale))
                .padding(.horizontal, 9 * scale)
                .padding(.vertical, 3 * scale)
                .background(
                    RoundedRectangle(cornerRadius: 5 * scale).fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5 * scale).strokeBorder(Color(nsColor: .separatorColor))
                )
                .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
    }
}

/// A slider drawn to scale: track, fill and thumb.
private struct ScaledSlider: View {
    @Binding var value: Double
    let scale: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let thumb = 14 * scale
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.15)).frame(height: 4 * scale)
                Capsule().fill(Color.accentColor).frame(width: max(0, width * value), height: 4 * scale)
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
                    .frame(width: thumb, height: thumb)
                    .offset(x: (width - thumb) * value)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    value = min(max(drag.location.x / max(width, 1), 0), 1)
                })
        }
        .frame(height: 16 * scale)
        .accessibilityRepresentation {
            Slider(value: $value, in: 0...1) { Text("Opacity") }
        }
    }
}

/// Normal or Difference, drawn to scale like a segmented control.
private struct BlendSwitch: View {
    @Binding var selection: ReferenceBlend
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 1 * scale) {
            segment(.normal, "Normal")
            segment(.difference, "Difference")
        }
        .padding(2 * scale)
        .background(RoundedRectangle(cornerRadius: 6 * scale).fill(Color.primary.opacity(0.08)))
    }

    private func segment(_ blend: ReferenceBlend, _ title: String) -> some View {
        Button {
            selection = blend
        } label: {
            Text(title)
                .font(.system(size: 11 * scale))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2 * scale)
                .background(
                    RoundedRectangle(cornerRadius: 4 * scale)
                        .fill(selection == blend ? Color(nsColor: .controlBackgroundColor) : .clear)
                        .shadow(color: .black.opacity(selection == blend ? 0.2 : 0), radius: 0.5, y: 0.5)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == blend ? .isSelected : [])
    }
}

/// A caption that scrubs its value, as in Unity: drag it left or right, one `step` per point of
/// travel, Shift ×10, Option ×0.1. Dotted underline and a ↔ cursor show it can be dragged.
private struct ScrubLabel: View {
    let title: String
    @Binding var value: Double
    let step: Double
    let scale: CGFloat
    /// The value when the drag began; the drag sets start + travel, so rounding in the binding
    /// never eats small steps.
    @State private var start: Double?

    var body: some View {
        Text(title)
            .font(.system(size: 11 * scale))
            .foregroundStyle(.secondary)
            .overlay(alignment: .bottom) {
                Line().stroke(style: StrokeStyle(lineWidth: 1, dash: [1, 2])).foregroundStyle(.secondary)
                    .frame(height: 1)
                    .offset(y: 1)
            }
            .padding(.vertical, 2 * scale)
            .contentShape(Rectangle())
            .onHover { inside in inside ? NSCursor.resizeLeftRight.push() : NSCursor.pop() }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { drag in
                        let from = start ?? value
                        start = from
                        let flags = NSEvent.modifierFlags
                        let factor = flags.contains(.shift) ? 10 : flags.contains(.option) ? 0.1 : 1
                        value = from + Double(drag.translation.width) * step * factor
                    }
                    .onEnded { _ in start = nil }
            )
            .help("Drag left or right to change; Shift for ×10, Option for ×0.1")
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}

/// A scrubbing caption, a number field that applies on Return or when focus leaves, and a unit.
private struct ScrubField: View {
    let title: String
    @Binding var value: Double
    let step: Double
    let unit: String?
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 4 * scale) {
            ScrubLabel(title: title, value: $value, step: step, scale: scale)
            TextField(title, value: $value, format: .number.precision(.fractionLength(0...1)))
                .textFieldStyle(.plain)
                .font(.system(size: 11 * scale).monospacedDigit())
                .multilineTextAlignment(.trailing)
                .padding(.horizontal, 5 * scale)
                .padding(.vertical, 2 * scale)
                .frame(width: 46 * scale)
                .background(RoundedRectangle(cornerRadius: 4 * scale).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 4 * scale).strokeBorder(Color(nsColor: .separatorColor)))
                .labelsHidden()
            if let unit {
                Text(unit).font(.system(size: 11 * scale)).foregroundStyle(.secondary)
            }
        }
    }
}

private struct Thumbnail: View {
    let image: CGImage?
    let scale: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable().interpolation(.none).scaledToFit()
            } else {
                Color.secondary.opacity(0.2)
            }
        }
        .frame(width: 30 * scale, height: 20 * scale)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 3 * scale))
    }
}
