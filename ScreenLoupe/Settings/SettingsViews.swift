import AppKit
import ServiceManagement
import SwiftUI

// The five tabs of the Settings window (docs/design.md §4, Settings).

struct GeneralSettingsView: View {
    let store: SettingsStore
    @State private var loginStatus = SMAppService.mainApp.status

    var body: some View {
        SettingsForm {
            SettingsRow(
                "Launch at login",
                note: loginStatus == .requiresApproval ? "Allow Screen Loupe in System Settings › Login Items." : nil
            ) {
                Toggle(
                    "Launch at login", isOn: Binding(get: { loginStatus == .enabled }, set: { setLaunchAtLogin($0) })
                )
                .labelsHidden()
            }
            .onAppear { loginStatus = SMAppService.mainApp.status }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                // Approving the login item happens in System Settings.
                loginStatus = SMAppService.mainApp.status
            }
            SettingsRow("Show in", note: "Menu bar only hides the Dock icon. Keep Viewer on Top hides it too while on.")
            {
                Picker("Show in", selection: store.binding(\.showsDockIcon)) {
                    Text("Dock and menu bar").tag(true)
                    Text("Menu bar only").tag(false)
                }
                .labelsHidden().fixedSize()
            }
            SettingsRow("On launch") {
                Picker("On launch", selection: store.binding(\.showsWindowsOnLaunch)) {
                    Text("Show Capture Area and Viewer").tag(true)
                    Text("Show nothing").tag(false)
                }
                .labelsHidden().fixedSize()
            }
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSSound.beep()
        }
        loginStatus = SMAppService.mainApp.status
    }
}

struct CaptureAreaSettingsView: View {
    let store: SettingsStore

    var body: some View {
        SettingsForm {
            SettingsRow("Frame color", note: "Line, handles and band. White reads on dark UIs.") {
                ColorSwatches(
                    presets: [
                        ("Blue", .blue), ("Orange", .amber), ("Pink", .pink), ("Green", .green), ("Purple", .purple),
                        ("White", .white),
                    ], selection: store.binding(\.frameColor))
            }
            SettingsRow("Line") {
                Picker("Line", selection: store.binding(\.frameLineWidth)) {
                    Text("1 pt").tag(1.0)
                    Text("2 pt").tag(2.0)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            SettingsRow("Size label at rest", note: "The muted W × H under the frame.") {
                Toggle("Size label at rest", isOn: store.binding(\.showsSizeAtRest)).labelsHidden()
            }
            SettingsRow("Size on the tab") {
                Picker("Size on the tab", selection: store.binding(\.sizeUnits)) {
                    Text("pt and px").tag(SizeUnits.pointsAndPixels)
                    Text("pt").tag(SizeUnits.points)
                    Text("px").tag(SizeUnits.pixels)
                }
                .labelsHidden().fixedSize()
            }
            SettingsRow("Preview") {
                FramePreview(settings: store.settings)
            }
        }
    }
}

struct ViewerSettingsView: View {
    let store: SettingsStore

    var body: some View {
        SettingsForm {
            SettingsRow("Background", note: "Around the image and where nothing is captured.") {
                Picker("Background", selection: store.binding(\.viewerBackground)) {
                    Text("Dark").tag(ViewerBackground.dark)
                    Text("Light").tag(ViewerBackground.light)
                    Text("Checkerboard").tag(ViewerBackground.checkerboard)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            SettingsRow("Pixel grid from", note: "The grid toggle shows it at this zoom and above.") {
                Picker("Pixel grid from", selection: store.binding(\.gridMinimumZoom)) {
                    ForEach([4.0, 6, 8, 12, 16, 24, 32], id: \.self) { zoom in
                        Text("\(Int(zoom))×").tag(zoom)
                    }
                }
                .labelsHidden().fixedSize()
            }
            SettingsRow("Grid lines", note: "Auto: dark over light pixels, light over dark.") {
                Picker("Grid lines", selection: store.binding(\.gridLines)) {
                    Text("Auto").tag(GridLines.auto)
                    Text("Dark").tag(GridLines.dark)
                    Text("Light").tag(GridLines.light)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            SettingsRow("Crosshair color") {
                ColorSwatches(
                    presets: [
                        ("Orange", .orange), ("Blue", .blue), ("Pink", .pink), ("Green", .green), ("White", .white),
                    ],
                    selection: store.binding(\.crosshairColor))
            }
            SettingsRow("Zoom with the wheel", note: "Without ⌘ the wheel pans. Trackpad scrolling always pans.") {
                Picker("Zoom with the wheel", selection: store.binding(\.wheelZoomNeedsCommand)) {
                    Text("Hold ⌘").tag(true)
                    Text("No key needed").tag(false)
                }
                .labelsHidden().fixedSize()
            }
        }
    }
}

struct ScreenshotSettingsView: View {
    let store: SettingsStore

    var body: some View {
        SettingsForm {
            SettingsRow("Save to", note: "Where Save View and Save Source start.") {
                HStack {
                    Text(folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .lineLimit(1).truncationMode(.middle)
                    Button("Choose…", action: chooseFolder)
                }
            }
            SettingsRow(
                "Pixel grid in Copy View", note: "Copy View and Save View, while the grid shows. Off by default."
            ) {
                Toggle("Pixel grid in Copy View", isOn: store.binding(\.gridInCopyView)).labelsHidden()
            }
            SettingsRow("File name") {
                Picker("File name", selection: store.binding(\.fileNameStyle)) {
                    ForEach(FileNameStyle.allCases, id: \.self) { style in
                        Text(ScreenshotExporter.fileName(kind: "View", style: style)).tag(style)
                    }
                }
                .labelsHidden().fixedSize()
            }
            SettingsRow("After saving") {
                Toggle("Show in Finder", isOn: store.binding(\.revealsSavedFile))
            }
        }
    }

    private var folder: URL {
        store.settings.screenshotDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = folder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.update { $0.screenshotDirectory = url.path }
    }
}

struct ShortcutSettingsView: View {
    let store: SettingsStore
    let shortcuts: GlobalShortcuts

    var body: some View {
        SettingsForm {
            ForEach(ShortcutAction.allCases, id: \.self) { action in
                SettingsRow(action.title, note: note(for: action)) {
                    ShortcutRecorder(
                        shortcut: binding(for: action), allowsLoneFunctionKey: action.allowsLoneFunctionKey
                    ) { shortcuts.isSuspended = $0 }
                }
            }
            Text("Click a shortcut and press new keys to change it. Delete clears it.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func note(for action: ShortcutAction) -> String? {
        if shortcuts.failed.contains(action) {
            return "macOS didn't accept this shortcut; it may be taken by another app. Try another."
        }
        switch action {
        case .copyView: return "Works from any app."
        case .toggleFreeze:
            return "Can be F13–F19 alone, so no modifier reaches the app you hold the mouse down in."
        default: return nil
        }
    }

    /// Taking a combination another action has clears it there, so no two actions share one.
    private func binding(for action: ShortcutAction) -> Binding<Shortcut?> {
        Binding(
            get: { store.settings.shortcuts[keyPath: action.keyPath] },
            set: { shortcut in
                store.update { settings in
                    if let shortcut {
                        for other in ShortcutAction.allCases
                        where settings.shortcuts[keyPath: other.keyPath]?.hasSameKeys(as: shortcut) == true {
                            settings.shortcuts[keyPath: other.keyPath] = nil
                        }
                    }
                    settings.shortcuts[keyPath: action.keyPath] = shortcut
                }
            })
    }
}

// MARK: - Building blocks

extension SettingsStore {
    func binding<Value>(_ keyPath: WritableKeyPath<Settings, Value>) -> Binding<Value> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { value in self.update { $0[keyPath: keyPath] = value } })
    }
}

/// A tab's content: labels right-aligned in the left column, controls in the right.
private struct SettingsForm<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Form { content }
            .formStyle(.columns)
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .frame(width: 560)
    }
}

/// One setting: its label, the control and an optional note under it.
private struct SettingsRow<Content: View>: View {
    let title: String
    let note: String?
    let content: Content

    init(_ title: String, note: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.note = note
        self.content = content()
    }

    var body: some View {
        LabeledContent(title) {
            VStack(alignment: .leading, spacing: 4) {
                content
                if let note {
                    Text(note).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Preset colour dots and a colour well for any other colour.
private struct ColorSwatches: View {
    let presets: [(name: String, color: SettingsColor)]
    @Binding var selection: SettingsColor

    var body: some View {
        HStack(spacing: 6) {
            ForEach(presets, id: \.color) { preset in
                Button {
                    selection = preset.color
                } label: {
                    Circle().fill(Color(nsColor: preset.color.nsColor))
                        .overlay(Circle().strokeBorder(.black.opacity(0.15)))
                        .frame(width: 18, height: 18)
                        .padding(3)
                        .overlay(
                            Circle().strokeBorder(Color.accentColor, lineWidth: 2).opacity(isSelected(preset) ? 1 : 0))
                }
                .buttonStyle(.plain)
                .help(preset.name)
                .accessibilityLabel(preset.name)
                .accessibilityAddTraits(isSelected(preset) ? .isSelected : [])
            }
            ColorPicker(
                "Custom color",
                selection: Binding(
                    get: { Color(nsColor: selection.nsColor) },
                    set: { selection = SettingsColor(NSColor($0)) }),
                supportsOpacity: false
            )
            .labelsHidden()
            .help("Custom color")
        }
    }

    private func isSelected(_ preset: (name: String, color: SettingsColor)) -> Bool {
        preset.color == selection
    }
}

/// The frame as it looks at rest, with the chosen colour, line and label.
private struct FramePreview: View {
    let settings: Settings

    var body: some View {
        let line = CGFloat(settings.frameLineWidth)
        VStack(spacing: 6) {
            Rectangle()
                .strokeBorder(Color(nsColor: settings.frameColor.nsColor), lineWidth: line)
                .frame(width: 110 + line * 2, height: 44 + line * 2)
            Text(SizeText.label(CGSize(width: 220, height: 150), scale: 2, units: settings.sizeUnits))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .frame(height: 16)
                .background(RoundedRectangle(cornerRadius: 4).fill(.black.opacity(0.62)))
                .opacity(settings.showsSizeAtRest ? 1 : 0)
        }
        .frame(width: 220, height: 96)
        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
    }
}
