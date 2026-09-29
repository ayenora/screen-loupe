import AppKit

/// The settings the frame is drawn with (Settings › Capture Area).
struct FrameStyleSettings: Equatable {
    var color: SettingsColor
    var lineWidth: Double
    var showsLabelAtRest: Bool
    /// Redraws the frame's labels when it changes; they read it from `OverlayStyle.labelFill`.
    var labelOpacity: Double
}

extension Settings {
    var frameStyleSettings: FrameStyleSettings {
        FrameStyleSettings(
            color: frameColor, lineWidth: frameLineWidth, showsLabelAtRest: showsSizeAtRest, labelOpacity: labelOpacity)
    }

    /// The Screenshot studio's frame: its own orange, the line and the label at rest as the Capture
    /// Area's.
    var studioFrameStyleSettings: FrameStyleSettings {
        FrameStyleSettings(
            color: .studio, lineWidth: frameLineWidth, showsLabelAtRest: showsSizeAtRest, labelOpacity: labelOpacity)
    }
}

/// The frame's colours and line, from Settings › Capture Area.
struct FrameStyle {
    var accent: NSColor
    /// 1 or 2 points.
    var lineWidth: CGFloat
    var showsLabelAtRest: Bool
    var band: NSColor { accent.withAlphaComponent(0.28) }
    /// The frame's sizes with this line width, for drawing and hit-testing alike.
    var metrics: OverlayMetrics {
        var metrics = OverlayMetrics.standard
        metrics.lineWidth = lineWidth
        return metrics
    }
    /// Darker than the accent, so the tab reads as a solid pill (`FrameTabColors`).
    var tabFill: NSColor
    /// The tab's text and grip: white where it reaches 4.5:1, else black (`FrameTabColors`).
    var onTab: NSColor
    /// White, or black when the accent itself is too light to outline a white handle.
    var handleFill: NSColor

    init(_ settings: FrameStyleSettings) {
        let color = settings.color
        accent = color.nsColor
        lineWidth = CGFloat(settings.lineWidth)
        showsLabelAtRest = settings.showsLabelAtRest
        let tab = FrameTabColors(accentRed: color.red, green: color.green, blue: color.blue)
        tabFill = SettingsColor(red: tab.red, green: tab.green, blue: tab.blue).nsColor
        onTab = tab.textIsWhite ? .white : .black
        handleFill = color.contrastRatio(with: .white) >= 1.5 ? .white : .black
    }
}

/// Fonts, sizes and timings of the Capture Area frame (the mockup's variant E).
@MainActor
enum OverlayStyle {
    /// Behind the labels, the position box, the margins panel and the buttons' names: black at
    /// Settings › Capture Area › Label background, which `AppController` keeps here.
    static var labelOpacity: CGFloat = 0.8
    static var labelFill: NSColor { NSColor.black.withAlphaComponent(labelOpacity) }
    /// The corners of the labels, the position box, the margins panel and its « button.
    static let labelCornerRadius: CGFloat = 4
    /// Keys, captions and units on the label fill.
    static let mutedText = NSColor.white.withAlphaComponent(0.6)
    static let tabFont = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
    static let labelFont = NSFont.systemFont(ofSize: 10, weight: .medium)
    /// The titles of the position box and the margins panel, while the margins are on.
    static let panelTitleFont = NSFont.systemFont(ofSize: 10, weight: .semibold)

    /// Tab: grip, gap, text, padding.
    static let tabLeading: CGFloat = 7
    static let gripWidth: CGFloat = 8
    static let tabGap: CGFloat = 6
    static let tabTrailing: CGFloat = 9
    static let labelPadding: CGFloat = 6

    static let revealDuration: TimeInterval = 0.12
    static let placementDuration: TimeInterval = 0.15
    /// How long the handles stay after the cursor leaves, so they don't flicker at the zone's edge.
    static let hideDelay: TimeInterval = 0.4
    /// How long a notice beside the tab stays, and how slowly it then fades.
    static let noticeDelay: TimeInterval = 2
    static let noticeFadeDuration: TimeInterval = 0.4

    /// The background of a label, the position box or the margins panel: `rect` in `labelFill`.
    static func fillLabel(_ rect: CGRect) {
        labelFill.setFill()
        NSBezierPath(roundedRect: rect, xRadius: labelCornerRadius, yRadius: labelCornerRadius).fill()
    }

    /// A thin contrasting outline around the line, so it reads on any background.
    static func halo(for appearance: NSAppearance) -> NSColor {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor.black.withAlphaComponent(0.55)
            : NSColor.white.withAlphaComponent(0.75)
    }

    /// Strokes the frame's line with its halo just outside `rect`, the captured rect in the view's
    /// coordinates, so every captured pixel stays visible.
    static func drawLine(around rect: CGRect, style: FrameStyle, appearance: NSAppearance) {
        let width = style.lineWidth
        let halo = NSBezierPath(rect: rect.insetBy(dx: -width - 0.5, dy: -width - 0.5))
        halo.lineWidth = 1
        self.halo(for: appearance).setStroke()
        halo.stroke()
        let line = NSBezierPath(rect: rect.insetBy(dx: -width / 2, dy: -width / 2))
        line.lineWidth = width
        style.accent.setStroke()
        line.stroke()
    }

    static func tabWidth(for text: String) -> CGFloat {
        let textWidth = (text as NSString).size(withAttributes: [.font: tabFont]).width
        return (tabLeading + gripWidth + tabGap + textWidth + tabTrailing).rounded(.up)
    }

    /// The L T R B box: a key column and a right-aligned value column, snug.
    static let positionPadding = CGSize(width: 6, height: 4)
    static let positionColumnGap: CGFloat = 6
    static let positionLineHeight: CGFloat = 13

    /// While the margins are on, the box has a title row and the margins panel's width
    /// (`MarginsPanelView`): enough for four-digit values, wider only for longer ones.
    static let positionTitleHeight: CGFloat = 16
    static let positionTitledWidth: CGFloat = 84
    /// Titled, the box and the margins panel are inset alike on every side, so the panel's 16 pt
    /// button sits as far from the top as from the right, and the rows start a gap below the title.
    static let titledPadding: CGFloat = 6
    static let titleGap: CGFloat = 4
    /// The top of the rows under a title.
    static let titledRowsTop = titledPadding + positionTitleHeight + titleGap

    static func positionSize(for lines: [(key: String, value: String)], titled: Bool = false) -> CGSize {
        let attributes: [NSAttributedString.Key: Any] = [.font: labelFont]
        let key = lines.map { ($0.key as NSString).size(withAttributes: attributes).width }.max() ?? 0
        let value = lines.map { ($0.value as NSString).size(withAttributes: attributes).width }.max() ?? 0
        let width = (positionPadding.width * 2 + key + positionColumnGap + value).rounded(.up)
        let rows = positionLineHeight * CGFloat(lines.count)
        guard titled else { return CGSize(width: width, height: positionPadding.height * 2 + rows) }
        return CGSize(width: max(width, positionTitledWidth), height: titledRowsTop + rows + titledPadding)
    }

    /// The title of the position box or the margins panel, centred in its row under the inset, in a
    /// flipped view. Returns where the text went.
    @discardableResult
    static func drawPanelTitle(_ title: String) -> CGRect {
        let attributes: [NSAttributedString.Key: Any] = [.font: panelTitleFont, .foregroundColor: NSColor.white]
        let size = (title as NSString).size(withAttributes: attributes)
        let origin = CGPoint(
            x: positionPadding.width, y: titledPadding + ((positionTitleHeight - size.height) / 2).rounded())
        (title as NSString).draw(at: origin, withAttributes: attributes)
        return CGRect(origin: origin, size: size)
    }

    /// The rows of the position box, or of the collapsed margins panel, in a flipped view of `bounds`
    /// from `top`: keys muted, values right-aligned.
    static func drawPositionLines(_ lines: [(key: String, value: String)], in bounds: CGRect, top: CGFloat) {
        let keyAttributes: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: mutedText]
        let valueAttributes: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: NSColor.white]
        let padding = positionPadding
        for (index, line) in lines.enumerated() {
            let y = top + CGFloat(index) * positionLineHeight
            (line.key as NSString).draw(at: CGPoint(x: padding.width, y: y), withAttributes: keyAttributes)
            let width = (line.value as NSString).size(withAttributes: valueAttributes).width
            (line.value as NSString).draw(
                at: CGPoint(x: bounds.width - padding.width - width, y: y), withAttributes: valueAttributes)
        }
    }

    static func labelWidth(for text: String) -> CGFloat {
        let textWidth = (text as NSString).size(withAttributes: [.font: labelFont]).width
        return (textWidth + labelPadding * 2).rounded(.up)
    }

    static func cursor(for target: OverlayHitTarget?) -> NSCursor {
        switch target {
        case nil: return .arrow
        case .pin, .pinMenu, .viewportButton, .moreButtons, .raiseViewer, .pickWindow, .marginsButton:
            return .pointingHand
        case .move, .viewportHandle: return .openHand
        case .resize(let handle): return resizeCursor(for: handle)
        }
    }

    private static func resizeCursor(for handle: OverlayHandle) -> NSCursor {
        if #available(macOS 15.0, *) {
            let position: NSCursor.FrameResizePosition
            switch handle {
            case .topLeft: position = .topLeft
            case .top: position = .top
            case .topRight: position = .topRight
            case .left: position = .left
            case .right: position = .right
            case .bottomLeft: position = .bottomLeft
            case .bottom: position = .bottom
            case .bottomRight: position = .bottomRight
            }
            return NSCursor.frameResize(position: position, directions: .all)
        }
        switch handle {
        case .left, .right: return .resizeLeftRight
        case .top, .bottom: return .resizeUpDown
        default: return .crosshair
        }
    }
}
