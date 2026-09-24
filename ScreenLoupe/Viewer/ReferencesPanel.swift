import AppKit
import SwiftUI

/// The References panel at the right of the Viewer (docs/product.md, References): the layers, top
/// first, like layers in an image editor. A layer is one row, or a block with its settings.
struct ReferencesPanel: View {
    let references: ReferencesController
    let window: () -> NSWindow?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("References").font(.headline)
                Spacer()
                Button("Add…") { references.addFromFiles(in: window()) }
                    .controlSize(.small)
                    .disabled(references.layers.count >= ReferenceStack.limit)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if references.layers.isEmpty {
                Text("Add an image — a design export or a screenshot — to lay it over the live pixels.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                Spacer()
            } else {
                List {
                    ForEach(references.layers) { layer in
                        LayerRow(references: references, layer: layer)
                            .listRowSeparator(.hidden)
                    }
                    .onMove { offsets, destination in
                        references.update { $0.move(fromOffsets: offsets, toOffset: destination) }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }

            Divider()
            Text("\(references.layers.count) of \(ReferenceStack.limit) · drag to reorder · top is on top")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
        }
        .frame(width: ColorMeterPanel.width)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct LayerRow: View {
    let references: ReferencesController
    let layer: ReferenceLayer

    private var isSelected: Bool { references.selectedID == layer.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button {
                    references.update(layer.id) { $0.isVisible.toggle() }
                } label: {
                    Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                        .frame(width: 16)
                }
                .buttonStyle(.plain)
                .help(layer.isVisible ? "Hide" : "Show")

                Thumbnail(image: references.image(for: layer))
                    .opacity(layer.isVisible ? 1 : 0.4)

                Text(layer.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .opacity(layer.isVisible ? 1 : 0.5)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("\(Int((layer.opacity * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Button {
                    references.update(layer.id) { $0.isPinned.toggle() }
                } label: {
                    Image(systemName: layer.isPinned ? "pin.fill" : "pin")
                        .frame(width: 14)
                }
                .buttonStyle(.plain)
                .help(
                    layer.isPinned ? "Unpin: drag it in the Viewer again" : "Pin: the mouse in the Viewer passes it by")

                Button {
                    references.update(layer.id) { $0.isExpanded.toggle() }
                } label: {
                    Image(systemName: layer.isExpanded ? "chevron.down" : "chevron.right")
                        .frame(width: 12)
                }
                .buttonStyle(.plain)
                .help(layer.isExpanded ? "Collapse" : "Expand")
            }

            if layer.isExpanded {
                LayerSettings(references: references, layer: layer)
                    .padding(.leading, 22)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(isSelected ? Color.accentColor.opacity(0.14) : .clear))
        .contentShape(Rectangle())
        .onTapGesture { references.select(layer.id) }
    }
}

private struct LayerSettings: View {
    let references: ReferencesController
    let layer: ReferenceLayer

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Opacity").foregroundStyle(.secondary)
                Slider(value: binding(\.opacity), in: 0...1)
                    .controlSize(.small)
            }
            Picker("Blend", selection: binding(\.blend)) {
                Text("Normal").tag(ReferenceBlend.normal)
                Text("Difference").tag(ReferenceBlend.difference)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            HStack(spacing: 8) {
                NumberField(title: "X", value: pointBinding(\.x), unit: nil)
                NumberField(title: "Y", value: pointBinding(\.y), unit: "px")
            }
            HStack(spacing: 8) {
                NumberField(title: "Scale", value: scaleBinding, unit: "%")
                Spacer()
            }
            HStack {
                Button("Reset Position") {
                    references.update(layer.id) {
                        $0.origin = .zero
                        $0.scale = 1
                    }
                }
                Spacer()
                Button("Delete", role: .destructive) { references.remove(layer.id) }
            }
            .controlSize(.small)
        }
        .font(.caption)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<ReferenceLayer, Value>) -> Binding<Value> {
        Binding(
            get: { layer[keyPath: keyPath] },
            set: { value in references.update(layer.id) { $0[keyPath: keyPath] = value } })
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

/// A caption, a number field that applies on Return or when focus leaves, and a unit.
private struct NumberField: View {
    let title: String
    @Binding var value: Double
    let unit: String?

    var body: some View {
        HStack(spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            TextField(title, value: $value, format: .number.precision(.fractionLength(0...1)))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 52)
            if let unit { Text(unit).foregroundStyle(.secondary) }
        }
    }
}

private struct Thumbnail: View {
    let image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable().interpolation(.none).scaledToFit()
            } else {
                Color.secondary.opacity(0.2)
            }
        }
        .frame(width: 28, height: 20)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
