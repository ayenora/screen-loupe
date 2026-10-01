import AppKit

/// A pilot: a row in the palette's Size menu to type a size in, W × H px, as the Size list had —
/// two text fields in a menu item's view. Return in either applies a valid size (`StudioSizes.parse`)
/// and closes the menu, an invalid one beeps; Tab goes from W to H and back; Escape closes the
/// menu. Whether a field in a menu takes the focus and typing while the menu tracks and the app
/// isn't active is to be checked live; without it, the row goes with this file and its one use in
/// `StudioController.showSizes`, and Custom Size… is the way to a size of one's own.
@MainActor
enum StudioSizeTypingItem {
    /// The menu item, calling `apply` with a valid typed size once the menu has closed.
    static func make(apply: @escaping (PixelSize) -> Void) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = TypingView(apply: apply)
        return item
    }
}

private final class TypingView: NSView, NSTextFieldDelegate {
    private let width = NSTextField()
    private let height = NSTextField()
    private let apply: (PixelSize) -> Void

    /// Where a menu item's title starts, past the checkmark column; the fields' width.
    private static let inset: CGFloat = 14
    private static let fieldWidth: CGFloat = 64

    init(apply: @escaping (PixelSize) -> Void) {
        self.apply = apply
        super.init(frame: .zero)
        for (field, placeholder) in [(width, "W"), (height, "H")] {
            field.placeholderString = placeholder
            field.bezelStyle = .roundedBezel
            field.delegate = self
            field.setAccessibilityLabel(placeholder == "W" ? "Width in pixels" : "Height in pixels")
            field.widthAnchor.constraint(equalToConstant: Self.fieldWidth).isActive = true
        }
        width.nextKeyView = height
        height.nextKeyView = width
        let times = NSTextField(labelWithString: "×")
        let unit = NSTextField(labelWithString: "px")
        for label in [times, unit] { label.textColor = .secondaryLabelColor }
        let row = NSStackView(views: [width, times, height, unit])
        row.spacing = 4
        row.edgeInsets = NSEdgeInsets(top: 3, left: Self.inset, bottom: 3, right: Self.inset)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        frame = CGRect(origin: .zero, size: row.fittingSize)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Return applies; Escape closes the menu.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            guard let size = StudioSizes.parse(width: width.stringValue, height: height.stringValue) else {
                NSSound.beep()
                return true
            }
            enclosingMenuItem?.menu?.cancelTracking()
            apply(size)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            enclosingMenuItem?.menu?.cancelTracking()
            return true
        default:
            return false
        }
    }
}
