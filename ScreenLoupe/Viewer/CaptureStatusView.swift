import AppKit

/// Shown over the Viewer when capturing failed for a reason other than permission, so the window is
/// never an unexplained empty rectangle (TASK.md §14).
final class CaptureStatusView: NSVisualEffectView {
    var onRetry: (() -> Void)?

    private let message = NSTextField(wrappingLabelWithString: "")

    init() {
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 12

        let title = NSTextField(labelWithString: "Capture stopped")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        message.alignment = .center
        message.textColor = .secondaryLabelColor
        message.preferredMaxLayoutWidth = 300
        let retry = NSButton(title: "Try Again", target: self, action: #selector(retryClicked))
        retry.keyEquivalent = "\r"

        let stack = NSStackView(views: [title, message, retry])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(message text: String) {
        message.stringValue = text
    }

    @objc private func retryClicked() {
        onRetry?()
    }
}
