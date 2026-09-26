import AppKit
import SwiftUI

// The Screenshot studio's sizes (docs/product.md, Screenshot studio): the Size list beside the
// palette and the Custom Sizes window. The sizes and the slot rules are `StudioSizes`.

/// The Size list: the presets, the custom sizes, a W × H row to type one, and Custom Size….
struct StudioSizeList: View {
    /// The frame's size in pixels, checked in the list.
    let current: PixelSize?
    let custom: [CustomSize]
    let apply: (PixelSize) -> Void
    let editCustomSizes: () -> Void

    @State private var width = ""
    @State private var height = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            section("Mac App Store", StudioSizes.appStore.map { ($0, StudioSizes.title($0), true) })
            section("Web", StudioSizes.web.map { ($0, StudioSizes.title($0), true) })
            if !custom.isEmpty {
                section("Custom", custom.map { ($0.pixels, StudioSizes.title($0), false) })
            }
            Divider().padding(.vertical, 4)
            HStack(spacing: 4) {
                TextField("W", text: $width).frame(width: 64)
                Text("×").foregroundStyle(.secondary)
                TextField("H", text: $height).frame(width: 64)
                Text("px").foregroundStyle(.secondary)
            }
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal, 8)
            .onSubmit(applyTyped)
            Divider().padding(.vertical, 4)
            SizeRow(title: "Custom Size…", isChecked: false, action: editCustomSizes)
        }
        .padding(6)
        .frame(width: 240)
    }

    private func section(_ title: String, _ sizes: [(size: PixelSize, title: String, isPreset: Bool)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 2)
            ForEach(sizes.indices, id: \.self) { index in
                let entry = sizes[index]
                SizeRow(
                    title: entry.title,
                    isChecked: StudioSizes.isChecked(entry.size, isPresetEntry: entry.isPreset, current: current)
                ) { apply(entry.size) }
            }
        }
    }

    /// Enter in W or H: the typed size, when both are valid.
    private func applyTyped() {
        guard let size = StudioSizes.parse(width: width, height: height) else { return NSSound.beep() }
        apply(size)
    }
}

/// A row of the Size list, highlighted under the pointer as a menu item is.
private struct SizeRow: View {
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

/// The Custom Sizes window: four slots, filled first; drag a filled slot to reorder it.
///
/// Rows keep a stable identity each (`ids`, moved with their sizes), so what a row holds never
/// passes to another after a remove or a move. Typing goes into a draft; Enter, moving to a field of
/// another slot, a click outside the fields, a ⊖ or Done takes the focused slot's draft first. Only
/// the window's close button drops it: the content is made anew each time the window opens.
struct CustomSizesView: View {
    let store: SettingsStore
    let done: () -> Void

    @State private var ids = (0..<StudioSizes.slotCount).map { _ in UUID() }
    @State private var drafts: [UUID: SlotDraft] = [:]
    @FocusState private var focus: SlotField?

    var body: some View {
        let sizes = store.settings.studioCustomSizes
        let slots = StudioSizes.slots(sizes)
        let firstEmpty = slots.firstIndex(of: nil)
        VStack(alignment: .leading, spacing: 12) {
            Text("Up to four sizes of your own, in pixels. They show under Custom in the Size list, in this order.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            List {
                ForEach(Array(zip(ids, slots).enumerated()), id: \.element.0) { index, row in
                    slotRow(id: row.0, slot: row.1, isEnabled: row.1 != nil || index == firstEmpty)
                        .moveDisabled(row.1 == nil)
                }
                .onMove { source, destination in
                    guard let from = source.first else { return }
                    let filled = StudioSizes.sanitized(sizes).count
                    ids = StudioSizes.moved(ids, from: from, to: destination, within: filled)
                    store.update {
                        $0.studioCustomSizes = StudioSizes.moving(from: from, to: destination, in: $0.studioCustomSizes)
                    }
                }
            }
            .listStyle(.bordered)
            .scrollDisabled(true)
            .frame(height: CGFloat(StudioSizes.slotCount) * 34 + 6)
            HStack {
                Spacer()
                Button("Done") {
                    commitFocused()
                    done()
                }
            }
        }
        .padding(20)
        .frame(width: 400)
        // A click outside the fields takes the focused slot.
        .background(
            Color.clear.contentShape(Rectangle()).onTapGesture {
                commitFocused()
                focus = nil
            }
        )
        .onChange(of: focus) { old, new in
            // Moving to a field of another slot takes the one left.
            if let old, let new, old.id != new.id { commit(old.id) }
        }
    }

    private func slotRow(id: UUID, slot: CustomSize?, isEnabled: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .opacity(slot == nil ? 0 : 1)
                .frame(width: 16)
            TextField("Name", text: text(id, slot, \.name))
                .focused($focus, equals: SlotField(id: id, part: .name))
            TextField("W", text: text(id, slot, \.width)).frame(width: 60)
                .focused($focus, equals: SlotField(id: id, part: .width))
            Text("×").foregroundStyle(.secondary)
            TextField("H", text: text(id, slot, \.height)).frame(width: 60)
                .focused($focus, equals: SlotField(id: id, part: .height))
            Text("px").foregroundStyle(.secondary)
            Button {
                commitFocused()
                remove(id)
            } label: {
                Image(systemName: "minus.circle.fill").foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Remove")
            .opacity(slot == nil ? 0 : 1)
            .disabled(slot == nil)
        }
        .textFieldStyle(.roundedBorder)
        .disabled(!isEnabled)
        .padding(.vertical, 2)
        .onSubmit { commit(id) }
    }

    /// A field's text: the slot's draft while it has one, else the saved slot.
    private func text(_ id: UUID, _ slot: CustomSize?, _ part: WritableKeyPath<SlotDraft, String>) -> Binding<String> {
        Binding(
            get: { (drafts[id] ?? SlotDraft(slot))[keyPath: part] },
            set: { value in
                var draft = drafts[id] ?? SlotDraft(slot)
                draft[keyPath: part] = value
                drafts[id] = draft
            })
    }

    /// Takes the slot's draft: a valid size fills the empty slot or changes the filled one. An
    /// invalid one is dropped on a filled slot, which shows its saved size again, and kept on the
    /// empty slot, where W may be typed before H.
    private func commit(_ id: UUID) {
        guard let draft = drafts[id], let index = ids.firstIndex(of: id) else { return }
        let sizes = store.settings.studioCustomSizes
        let isFilled = index < StudioSizes.sanitized(sizes).count
        guard let size = StudioSizes.parse(width: draft.width, height: draft.height) else {
            if isFilled { drafts[id] = nil }
            return
        }
        drafts[id] = nil
        let custom = CustomSize(name: draft.name, width: size.width, height: size.height)
        store.update {
            $0.studioCustomSizes =
                isFilled
                ? StudioSizes.replacing(at: index, with: custom, in: $0.studioCustomSizes)
                : StudioSizes.adding(custom, to: $0.studioCustomSizes)
        }
    }

    private func commitFocused() {
        if let focused = focus?.id { commit(focused) }
    }

    /// The slot's identity goes to the bottom with the empty slot its removal leaves.
    private func remove(_ id: UUID) {
        guard let index = ids.firstIndex(of: id) else { return }
        drafts[id] = nil
        ids = StudioSizes.moved(ids, from: index, to: ids.count, within: ids.count)
        store.update { $0.studioCustomSizes = StudioSizes.removing(at: index, from: $0.studioCustomSizes) }
    }
}

private struct SlotField: Hashable {
    enum Part { case name, width, height }
    let id: UUID
    let part: Part
}

/// What a slot's fields hold while being edited.
private struct SlotDraft {
    var name: String
    var width: String
    var height: String

    init(_ slot: CustomSize?) {
        name = slot?.name ?? ""
        width = slot.map { String($0.width) } ?? ""
        height = slot.map { String($0.height) } ?? ""
    }
}

// MARK: - The Size list's panel

/// The Size list beside the palette: a non-activating panel in the pop-over's look. A click on a
/// size works without activating the app; a click in W or H makes only this panel key, so typing
/// reaches it while the app the user works in stays active and none of this app's other windows
/// come forward. Closed by a size, Escape, the Size button, a drag of the palette, hiding the
/// studio, or a click outside it and the palette.
@MainActor
final class StudioSizePanel: NSPanel {
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
    func show(_ list: StudioSizeList, beside palette: NSWindow, origin: (CGSize) -> CGPoint) {
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
