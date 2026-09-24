import AppKit

/// Shown over the Viewer while capturing is interrupted, so the window is never an unexplained empty
/// rectangle (TASK.md §14).
///
/// Reconnecting: a spinner, the attempt number, a countdown to the next try and Try Now.
/// Failed (all automatic attempts used up): the reason and Try Again.
final class CaptureStatusView: NSVisualEffectView {
    var onRetry: (() -> Void)?
    var onRestart: (() -> Void)?

    private let spinner = NSProgressIndicator()
    private let title = NSTextField(labelWithString: "")
    private let progress = NSTextField(labelWithString: "")
    private let reason = NSTextField(wrappingLabelWithString: "")
    private let button = NSButton(title: "", target: nil, action: nil)
    private let restartButton = NSButton(title: "Restart Screen Loupe", target: nil, action: nil)
    private var countdown: Timer?
    private var attempt = 0
    private var maxAttempts = 0
    private var nextAttempt: Date?

    init() {
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 12

        spinner.style = .spinning
        spinner.controlSize = .small
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        progress.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        progress.textColor = .secondaryLabelColor
        reason.alignment = .center
        reason.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        reason.textColor = .tertiaryLabelColor
        reason.preferredMaxLayoutWidth = 300
        button.target = self
        button.action = #selector(retryClicked)
        button.keyEquivalent = "\r"
        restartButton.target = self
        restartButton.action = #selector(restartClicked)
        restartButton.isHidden = true
        let buttons = NSStackView(views: [button, restartButton])
        buttons.spacing = 12

        let heading = NSStackView(views: [spinner, title])
        heading.spacing = 8
        let stack = NSStackView(views: [heading, progress, reason, buttons])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.setCustomSpacing(14, after: reason)
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 300),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Capture is being restored. `nextAttempt` is `nil` while an attempt is running.
    @MainActor
    func showReconnecting(reason text: String, attempt: Int, of maxAttempts: Int, nextAttempt: Date?) {
        title.stringValue = "Capture interrupted"
        reason.stringValue = text
        button.title = "Try Now"
        button.keyEquivalent = "\r"
        restartButton.isHidden = true
        spinner.isHidden = false
        spinner.startAnimation(nil)
        self.attempt = attempt
        self.maxAttempts = maxAttempts
        self.nextAttempt = nextAttempt
        updateProgress()
        countdown?.invalidate()
        countdown = nil
        if nextAttempt != nil {
            countdown = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateProgress() }
            }
        }
    }

    /// Every automatic attempt failed. After a Try Again that didn't help either, the panel suggests
    /// relaunching the app and makes that the default button.
    @MainActor
    func showFailed(reason text: String, afterUserRetry: Bool) {
        countdown?.invalidate()
        countdown = nil
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        title.stringValue = "Capture stopped"
        progress.stringValue =
            afterUserRetry
            ? "Try quitting and reopening Screen Loupe." : "Screen Loupe couldn't restore the capture."
        reason.stringValue = text
        button.title = "Try Again"
        button.keyEquivalent = afterUserRetry ? "" : "\r"
        restartButton.keyEquivalent = afterUserRetry ? "\r" : ""
        restartButton.isHidden = !afterUserRetry
    }

    /// Stops the countdown when the panel goes away.
    @MainActor
    func stop() {
        countdown?.invalidate()
        countdown = nil
        spinner.stopAnimation(nil)
    }

    @MainActor
    private func updateProgress() {
        let counter = "attempt \(attempt) of \(maxAttempts)"
        guard let nextAttempt else {
            progress.stringValue = "Reconnecting — \(counter), trying now…"
            return
        }
        let seconds = max(1, Int(nextAttempt.timeIntervalSinceNow.rounded(.up)))
        progress.stringValue = "Reconnecting — \(counter) in \(seconds) s"
    }

    @objc private func retryClicked() {
        onRetry?()
    }

    @objc private func restartClicked() {
        onRestart?()
    }
}

/// A confirmation that fades in at the bottom of the Viewer and out again after a moment.
final class ToastView: NSVisualEffectView {
    private let label = NSTextField(labelWithString: "")
    private var hideTask: Task<Void, Never>?

    init() {
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 8
        alphaValue = 0
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    @MainActor
    func show(_ text: String) {
        label.stringValue = text
        hideTask?.cancel()
        NSAnimationContext.runAnimationGroup {
            $0.duration = 0.12; animator().alphaValue = 1
        }
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled, let self else { return }
            NSAnimationContext.runAnimationGroup(
                {
                    $0.duration = 0.3; self.animator().alphaValue = 0
                }, completionHandler: nil)
        }
    }
}
