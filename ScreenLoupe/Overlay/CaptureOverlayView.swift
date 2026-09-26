import AppKit

@MainActor
protocol CaptureOverlayViewDelegate: AnyObject {
    /// Points are in AppKit global coordinates.
    func overlayView(_ view: CaptureOverlayView, hitTargetAt point: CGPoint) -> OverlayHitTarget?
    func overlayView(_ view: CaptureOverlayView, mouseDownAt point: CGPoint)
    func overlayView(_ view: CaptureOverlayView, mouseDraggedTo point: CGPoint)
    func overlayViewMouseUp(_ view: CaptureOverlayView)
    /// A lock was chosen from the pin's ▾.
    func overlayView(_ view: CaptureOverlayView, didChoose lock: CaptureAreaLock)
    /// Returns whether the key was handled.
    func overlayView(_ view: CaptureOverlayView, keyDown event: NSEvent) -> Bool
}

/// Draws the Capture Area frame and turns mouse and key events into delegate calls.
///
/// The line is always drawn. The band, the handles, the tab and the position box fade in on hover;
/// the muted size label shows at rest. A frame whose lock stops resizing shows no band or handles.
/// The dashed outline of the part the Viewer shows, and a notice beside the tab, fade in and out as
/// the controller asks.
/// Subviews never take the mouse, so every event lands here.
final class CaptureOverlayView: NSView {
    weak var delegate: CaptureOverlayViewDelegate?

    private var layout: OverlayLayout?
    private let decorations = FrameDecorationsView()
    private let viewedPartOutline = ViewedPartView()
    private let tab = GripTabView()
    private let label = SizeLabelView()
    private let positionBox = PositionBoxView()
    /// Says why the magnet let go.
    private let notice = SizeLabelView()
    /// The pin with its ▾: shows the chosen lock, filled while it is on.
    private let pinButton = TabButtonView(
        image: CaptureAreaLock.pinned.image(isOn: false), onImage: CaptureAreaLock.pinned.image(isOn: true))
    /// Brings the Viewer forward, for when a click in the area sent another app's window over it.
    private let raiseButton = TabButtonView(
        image: TabButtonView.symbol("arrow.up.forward.app"), onImage: TabButtonView.symbol("arrow.up.forward.app"))
    /// Picks a window for the area to take.
    private let pickButton = TabButtonView(
        image: TabButtonView.symbol("macwindow"), onImage: TabButtonView.symbol("macwindow"))
    private var isDragging = false
    private var isRevealed = false
    private var isViewedPartShown = false

    /// The part of the area the Viewer shows, in AppKit global coordinates.
    var viewedPart: CGRect? {
        didSet { placeViewedPart() }
    }

    /// The lock chosen with the pin's ▾, shown by the pin's image.
    var lock = CaptureAreaLock.pinned {
        didSet {
            pinButton.image = lock.image(isOn: false)
            pinButton.onImage = lock.image(isOn: true)
            decorations.alphaValue = decorationsAlpha
        }
    }

    /// Locked: the pin is filled, and the band and handles show only if the lock lets them resize. A
    /// band that doesn't move the frame still shows: the panel takes presses only on drawn pixels, and
    /// the band lets a handle take one across its whole hit square.
    var isLocked = false {
        didSet {
            pinButton.isOn = isLocked
            decorations.alphaValue = decorationsAlpha
        }
    }

    private var activeLock: CaptureAreaLock? { isLocked ? lock : nil }

    var style: FrameStyle {
        didSet {
            decorations.style = style
            viewedPartOutline.style = style
            tab.style = style
            pinButton.style = style
            raiseButton.style = style
            pickButton.style = style
            label.alphaValue = labelAlpha
            needsDisplay = true
        }
    }

    init(style: FrameStyle) {
        self.style = style
        decorations.style = style
        viewedPartOutline.style = style
        tab.style = style
        pinButton.style = style
        raiseButton.style = style
        pickButton.style = style
        super.init(frame: .zero)
        wantsLayer = true
        autoresizingMask = [.width, .height]
        for subview in [
            viewedPartOutline, decorations, label, positionBox, tab, pinButton, raiseButton, pickButton, notice,
        ] as [NSView] {
            addSubview(subview)
        }
        decorations.alphaValue = 0
        viewedPartOutline.alphaValue = 0
        tab.alphaValue = 0
        positionBox.alphaValue = 0
        notice.alphaValue = 0
        pinButton.menuWidth = OverlayMetrics.standard.pinMenuWidth
        pinButton.menuLabel = "Pin Mode"
        pinButton.alphaValue = 0
        raiseButton.alphaValue = 0
        pickButton.alphaValue = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: State

    /// Lays the frame out. Call after the window has taken `layout.windowFrame`.
    func update(
        layout: OverlayLayout, tabText: String, labelText: String, positionLines: [(key: String, value: String)]
    ) {
        let placementChanged = self.layout.map { $0.tabPlacement != layout.tabPlacement } ?? false
        self.layout = layout

        decorations.frame = bounds
        decorations.captureRect = local(layout.captureRect)
        viewedPartOutline.frame = bounds
        placeViewedPart()
        decorations.handleRects = OverlayHandle.allCases.map {
            local(layout.handleRect($0, size: OverlayMetrics.standard.handleSize))
        }
        label.text = labelText
        label.frame = local(layout.labelRect)
        positionBox.lines = positionLines
        positionBox.frame = local(layout.positionRect)
        notice.frame = local(layout.noticeRect)
        pinButton.frame = local(layout.pinRect.union(layout.pinMenuRect))
        raiseButton.frame = local(layout.raiseRect)
        pickButton.frame = local(layout.pickRect)
        tab.text = tabText
        tab.showsShadow = layout.tabPlacement == .inside

        let tabFrame = local(layout.tabRect)
        if placementChanged {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = OverlayStyle.placementDuration
                context.allowsImplicitAnimation = true
                tab.animator().frame = tabFrame
            }
        } else {
            tab.frame = tabFrame
        }
        needsDisplay = true
    }

    /// Shows the band, handles and tab (hover), or the muted size label (rest).
    func setRevealed(_ revealed: Bool) {
        isRevealed = revealed
        NSAnimationContext.runAnimationGroup { context in
            context.duration = OverlayStyle.revealDuration
            decorations.animator().alphaValue = decorationsAlpha
            tab.animator().alphaValue = revealed ? 1 : 0
            positionBox.animator().alphaValue = revealed ? 1 : 0
            pinButton.animator().alphaValue = revealed ? 1 : 0
            raiseButton.animator().alphaValue = revealed ? 1 : 0
            pickButton.animator().alphaValue = revealed ? 1 : 0
            label.animator().alphaValue = labelAlpha
        }
    }

    /// Fades the outline of the viewed part in or out.
    func setViewedPartShown(_ shown: Bool) {
        guard shown != isViewedPartShown else { return }
        isViewedPartShown = shown
        placeViewedPart()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = OverlayStyle.revealDuration
            viewedPartOutline.animator().alphaValue = shown ? 1 : 0
        }
    }

    /// Shows `text` beside the tab at once, or fades the notice out when `nil`. The layout must
    /// already make room for it.
    func setNotice(_ text: String?) {
        if let text {
            notice.text = text
            // A notice shown again while it fades comes back at once.
            notice.layer?.removeAllAnimations()
            notice.alphaValue = 1
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = OverlayStyle.noticeFadeDuration
                notice.animator().alphaValue = 0
            }
        }
    }

    /// A hidden outline isn't redrawn, and one whose part is gone fades out where it last was.
    private func placeViewedPart() {
        guard isViewedPartShown, let layout, let viewedPart else { return }
        viewedPartOutline.captureRect = local(layout.captureRect)
        viewedPartOutline.viewedRect = local(viewedPart)
    }

    private var labelAlpha: CGFloat { !isRevealed && style.showsLabelAtRest ? 1 : 0 }
    private var decorationsAlpha: CGFloat { isRevealed && activeLock?.allowsResize != false ? 1 : 0 }

    private func local(_ rect: CGRect) -> CGRect {
        guard let origin = layout?.windowFrame.origin else { return rect }
        return rect.offsetBy(dx: -origin.x, dy: -origin.y)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let layout else { return }
        let rect = local(layout.captureRect)
        let width = style.lineWidth
        // The line sits just outside the captured rect, so every captured pixel stays visible.
        let halo = NSBezierPath(rect: rect.insetBy(dx: -width - 0.5, dy: -width - 0.5))
        halo.lineWidth = 1
        OverlayStyle.halo(for: effectiveAppearance).setStroke()
        halo.stroke()
        let line = NSBezierPath(rect: rect.insetBy(dx: -width / 2, dy: -width / 2))
        line.lineWidth = width
        style.accent.setStroke()
        line.stroke()
    }

    // MARK: Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
                owner: self
            )
        )
    }

    override func mouseMoved(with event: NSEvent) { updateCursor() }
    override func cursorUpdate(with event: NSEvent) { updateCursor() }

    override func mouseExited(with event: NSEvent) {
        if !isDragging { NSCursor.arrow.set() }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        isDragging = true
        let point = NSEvent.mouseLocation
        let target = delegate?.overlayView(self, hitTargetAt: point)
        if target == .move || (target == nil && !isLocked) {
            NSCursor.closedHand.set()
        }
        delegate?.overlayView(self, mouseDownAt: point)
    }

    override func mouseDragged(with event: NSEvent) {
        delegate?.overlayView(self, mouseDraggedTo: NSEvent.mouseLocation)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        delegate?.overlayViewMouseUp(self)
        updateCursor()
    }

    private func updateCursor() {
        guard !isDragging else { return }
        OverlayStyle.cursor(for: delegate?.overlayView(self, hitTargetAt: NSEvent.mouseLocation)).set()
    }

    // MARK: Lock menu

    /// Pops the menu of locks up under the pin's ▾, the chosen one checked.
    func showLockMenu() {
        guard let layout else { return }
        let menu = NSMenu()
        for (index, lock) in CaptureAreaLock.allCases.enumerated() {
            let item = menu.addItem(withTitle: lock.menuTitle, action: #selector(lockChosen(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.image = lock.image(isOn: false)
            item.state = lock == self.lock ? .on : .off
        }
        let pin = local(layout.pinRect)
        menu.popUp(positioning: nil, at: CGPoint(x: pin.minX, y: pin.minY - 4), in: self)
        // The menu took the mouse-up.
        isDragging = false
        updateCursor()
    }

    @objc private func lockChosen(_ sender: NSMenuItem) {
        delegate?.overlayView(self, didChoose: CaptureAreaLock.allCases[sender.tag])
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        if delegate?.overlayView(self, keyDown: event) != true {
            super.keyDown(with: event)
        }
    }
}

/// The band outside the line and the eight resize handles.
private final class FrameDecorationsView: NSView {
    var captureRect: CGRect = .zero { didSet { needsDisplay = true } }
    var handleRects: [CGRect] = [] { didSet { needsDisplay = true } }
    var style: FrameStyle? { didSet { needsDisplay = true } }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let style else { return }
        let metrics = style.metrics
        let outer = metrics.lineWidth + metrics.bandWidth
        let band = NSBezierPath(rect: captureRect.insetBy(dx: -outer, dy: -outer))
        band.append(NSBezierPath(rect: captureRect.insetBy(dx: -style.lineWidth, dy: -style.lineWidth)))
        band.windingRule = .evenOdd
        style.band.setFill()
        band.fill()

        for rect in handleRects {
            style.handleFill.setFill()
            rect.fill()
            let outline = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            outline.lineWidth = 1
            style.accent.setStroke()
            outline.stroke()
        }
    }
}

/// The part of the area the Viewer shows: a 1 pt dashed line in the accent with the line's halo,
/// inside the captured rect so it never covers the frame's line.
private final class ViewedPartView: NSView {
    var captureRect: CGRect = .zero { didSet { needsDisplay = true } }
    var viewedRect: CGRect? { didSet { needsDisplay = true } }
    var style: FrameStyle? { didSet { needsDisplay = true } }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let style, let viewedRect else { return }
        NSBezierPath(rect: captureRect).setClip()
        let rect = viewedRect.insetBy(dx: 0.5, dy: 0.5)
        let dashes: [CGFloat] = [4, 3]
        let halo = NSBezierPath(rect: rect)
        halo.lineWidth = 3
        halo.setLineDash(dashes, count: dashes.count, phase: 0)
        OverlayStyle.halo(for: effectiveAppearance).setStroke()
        halo.stroke()
        let line = NSBezierPath(rect: rect)
        line.lineWidth = 1
        line.setLineDash(dashes, count: dashes.count, phase: 0)
        style.accent.setStroke()
        line.stroke()
    }
}

/// The pill above the frame: a grip and the size in points and pixels. Dragging it moves the frame.
private final class GripTabView: NSView {
    var text = "" { didSet { if text != oldValue { needsDisplay = true } } }
    var style: FrameStyle? { didSet { needsDisplay = true } }
    var showsShadow = false {
        didSet {
            layer?.shadowOpacity = showsShadow ? 0.45 : 0
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowRadius = 3
        layer?.shadowOffset = CGSize(width: 0, height: -1)
        layer?.shadowOpacity = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let style else { return }
        let radius = bounds.height / 2
        style.tabFill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()

        // Grip: two columns of three dots in an 8 × 12 box.
        style.onTab.setFill()
        let gripOrigin = CGPoint(x: OverlayStyle.tabLeading, y: (bounds.height - 12) / 2)
        for column in 0..<2 {
            for row in 0..<3 {
                let center = CGPoint(x: gripOrigin.x + 2 + CGFloat(column) * 4, y: gripOrigin.y + 2 + CGFloat(row) * 4)
                NSBezierPath(ovalIn: CGRect(x: center.x - 1.2, y: center.y - 1.2, width: 2.4, height: 2.4)).fill()
            }
        }

        let attributes: [NSAttributedString.Key: Any] = [.font: OverlayStyle.tabFont, .foregroundColor: style.onTab]
        let size = (text as NSString).size(withAttributes: attributes)
        let x = OverlayStyle.tabLeading + OverlayStyle.gripWidth + OverlayStyle.tabGap
        (text as NSString).draw(
            at: CGPoint(x: x, y: ((bounds.height - size.height) / 2).rounded()), withAttributes: attributes)
    }
}

/// A square button beside the tab — the pin, the raise and pick buttons: the tab's colour with an outlined
/// image, or the accent with the filled one while it is on. The images are templates, drawn in the tint.
/// The pin carries a ▾ on its right, past a thin divider.
private final class TabButtonView: NSView {
    var style: FrameStyle? { didSet { needsDisplay = true } }
    var isOn = false { didSet { needsDisplay = true } }
    var image: NSImage? { didSet { needsDisplay = true } }
    var onImage: NSImage? { didSet { needsDisplay = true } }
    /// The ▾ part's width; 0 for a plain button.
    var menuWidth: CGFloat = 0 { didSet { needsDisplay = true } }
    var menuLabel = ""

    /// An SF Symbol at the buttons' size and weight.
    nonisolated static func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
    }

    init(image: NSImage?, onImage: NSImage?) {
        self.image = image
        self.onImage = onImage
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let style else { return }
        (isOn ? style.accent : style.tabFill).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        let tint = isOn ? (style.handleFill == .white ? NSColor.white : .black) : style.onTab
        let button = CGRect(x: 0, y: 0, width: bounds.width - menuWidth, height: bounds.height)
        if let image = isOn ? onImage : image {
            draw(tinted(image, tint), in: button)
        }
        guard menuWidth > 0 else { return }
        tint.withAlphaComponent(0.35).setFill()
        CGRect(x: button.maxX, y: 4, width: 1, height: bounds.height - 8).fill()
        let colour = NSImage.SymbolConfiguration(paletteColors: [tint])
        guard
            let chevron = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: menuLabel)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 7, weight: .bold).applying(colour))
        else { return }
        draw(chevron, in: CGRect(x: button.maxX, y: 0, width: menuWidth, height: bounds.height))
    }

    /// The template image in the tint, drawn at the destination's resolution.
    private func tinted(_ image: NSImage, _ tint: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            tint.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    private func draw(_ image: NSImage, in rect: CGRect) {
        image.draw(
            in: CGRect(
                x: (rect.minX + (rect.width - image.size.width) / 2).rounded(),
                y: ((rect.height - image.size.height) / 2).rounded(),
                width: image.size.width, height: image.size.height))
    }
}

/// The L T R B box beside the frame: keys muted, values right-aligned.
private final class PositionBoxView: NSView {
    var lines: [(key: String, value: String)] = [] { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        OverlayStyle.labelFill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        let keyAttributes: [NSAttributedString.Key: Any] = [
            .font: OverlayStyle.labelFont, .foregroundColor: NSColor.white.withAlphaComponent(0.6),
        ]
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: OverlayStyle.labelFont, .foregroundColor: NSColor.white,
        ]
        let padding = OverlayStyle.positionPadding
        for (index, line) in lines.enumerated() {
            let y = padding.height + CGFloat(index) * OverlayStyle.positionLineHeight
            (line.key as NSString).draw(at: CGPoint(x: padding.width, y: y), withAttributes: keyAttributes)
            let width = (line.value as NSString).size(withAttributes: valueAttributes).width
            (line.value as NSString).draw(
                at: CGPoint(x: bounds.width - padding.width - width, y: y), withAttributes: valueAttributes)
        }
    }
}

/// The muted size shown at rest, and the notice beside the tab.
private final class SizeLabelView: NSView {
    var text = "" { didSet { if text != oldValue { needsDisplay = true } } }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        OverlayStyle.labelFill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: OverlayStyle.labelFont, .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(
            at: CGPoint(
                x: ((bounds.width - size.width) / 2).rounded(), y: ((bounds.height - size.height) / 2).rounded()),
            withAttributes: attributes
        )
    }
}

/// The pin's ▾ menu and images. SF Symbols has no anchor and no magnet, so Fixed Position and Magnet
/// show Lucide's (THIRD_PARTY_NOTICES.md), from the asset catalog: 14 pt, stroked to match the pin.
extension CaptureAreaLock {
    fileprivate var title: String {
        switch self {
        case .pinned: "Pinned"
        case .fixedPosition: "Fixed Position"
        case .magnet: "Magnet to Window"
        }
    }

    /// Choosing the magnet opens the window picker first.
    fileprivate var menuTitle: String { self == .magnet ? "\(title)…" : title }

    /// A template image, outlined, or filled while on where the shape has a filled form.
    fileprivate func image(isOn: Bool) -> NSImage? {
        switch self {
        case .pinned: TabButtonView.symbol(isOn ? "pin.fill" : "pin")
        case .fixedPosition: NSImage(named: "anchor")
        case .magnet: NSImage(named: "magnet")
        }
    }
}
