import AppKit

/// Shown in the Viewer instead of the capture while Screen Recording access is missing (TASK.md §14).
final class PermissionView: NSView {
    private let permissions: PermissionsManager

    init(permissions: PermissionsManager) {
        self.permissions = permissions
        super.init(frame: .zero)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func build() {
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "display", accessibilityDescription: nil)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 40, weight: .light)
        icon.contentTintColor = .secondaryLabelColor

        let title = NSTextField(labelWithString: "Screen Recording access is needed")
        title.font = .systemFont(ofSize: 17, weight: .semibold)

        let body = NSTextField(
            wrappingLabelWithString:
                "Screen Loupe shows the Capture Area by capturing that part of the screen with ScreenCaptureKit. "
                + "Frames are only drawn in this window. Nothing is recorded, saved or sent anywhere."
        )
        body.alignment = .center
        body.textColor = .secondaryLabelColor
        body.preferredMaxLayoutWidth = 380

        let grant = NSButton(title: "Grant Access…", target: self, action: #selector(grantAccess))
        grant.keyEquivalent = "\r"
        let settings = NSButton(title: "Open System Settings", target: self, action: #selector(openSettings))
        let buttons = NSStackView(views: [settings, grant])
        buttons.spacing = 12

        let note = NSTextField(
            wrappingLabelWithString: "Already allowed it in System Settings? macOS applies the change after a restart."
        )
        note.alignment = .center
        note.font = .systemFont(ofSize: 11)
        note.textColor = .tertiaryLabelColor
        note.preferredMaxLayoutWidth = 380
        let restart = NSButton(title: "Restart Screen Loupe", target: self, action: #selector(restart))
        restart.controlSize = .small

        let stack = NSStackView(views: [icon, title, body, buttons, note, restart])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.setCustomSpacing(20, after: body)
        stack.setCustomSpacing(24, after: buttons)
        stack.setCustomSpacing(6, after: note)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            stack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 24),
        ])
    }

    @objc private func grantAccess() {
        permissions.requestScreenRecordingAccess()
    }

    @objc private func openSettings() {
        permissions.openScreenRecordingSettings()
    }

    @objc private func restart() {
        permissions.relaunch()
    }
}
