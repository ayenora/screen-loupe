import AppKit

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
    /// Darker than the accent, so the tab reads as a solid pill.
    var tabFill: NSColor
    /// White or black, whichever reaches 4.5:1 on the tab: its text and grip.
    var onTab: NSColor
    /// White, or black when the accent itself is too light to outline a white handle.
    var handleFill: NSColor

    init(color: SettingsColor, lineWidth: Double, showsLabelAtRest: Bool) {
        accent = color.nsColor
        self.lineWidth = CGFloat(lineWidth)
        self.showsLabelAtRest = showsLabelAtRest
        let dark = SettingsColor(red: color.red * 0.78, green: color.green * 0.78, blue: color.blue * 0.78)
        tabFill = dark.nsColor
        onTab = dark.contrastRatio(with: SettingsColor(255, 255, 255)) >= 4.5 ? .white : .black
        handleFill = color.contrastRatio(with: SettingsColor(255, 255, 255)) >= 1.5 ? .white : .black
    }
}

/// Fonts, sizes and timings of the Capture Area frame (the mockup's variant E).
@MainActor
enum OverlayStyle {
    static let labelFill = NSColor.black.withAlphaComponent(0.62)
    static let tabFont = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
    static let labelFont = NSFont.systemFont(ofSize: 10, weight: .medium)

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

    /// A thin contrasting outline around the line, so it reads on any background.
    static func halo(for appearance: NSAppearance) -> NSColor {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor.black.withAlphaComponent(0.55)
            : NSColor.white.withAlphaComponent(0.75)
    }

    static func tabWidth(for text: String) -> CGFloat {
        let textWidth = (text as NSString).size(withAttributes: [.font: tabFont]).width
        return (tabLeading + gripWidth + tabGap + textWidth + tabTrailing).rounded(.up)
    }

    static func labelWidth(for text: String) -> CGFloat {
        let textWidth = (text as NSString).size(withAttributes: [.font: labelFont]).width
        return (textWidth + labelPadding * 2).rounded(.up)
    }

    static func cursor(for target: OverlayHitTarget?) -> NSCursor {
        switch target {
        case nil: return .arrow
        case .move: return .openHand
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
