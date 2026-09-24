import AppKit
import Observation

/// State kept between launches (docs/product.md, Kept between launches) and the choices made in the Settings window. The
/// Viewer frame is kept by AppKit through its autosave name; everything else lives here.
struct Settings: Codable, Equatable {
    /// Capture Area in AppKit global coordinates.
    var captureArea: CGRect?
    /// A pinned Capture Area neither moves nor resizes.
    var captureAreaPinned = false
    /// Keep the Viewer above the windows of other apps.
    var viewerAlwaysOnTop = false
    /// Where screenshots are saved; the Desktop when unset.
    var screenshotDirectory: String?
    /// Viewer overlays and the Color Meter panel.
    var gridEnabled = false
    var crosshairEnabled = true
    var meterVisible = false
    var referencesVisible = false
    /// With both side panels open, the one that is expanded.
    var expandedSidePanel = SidePanel.colorMeter
    /// The side panel column's width in points; its content scales with it.
    var sidePanelWidth = Double(SidePanel.widthRange.lowerBound)
    var pinnedColors: [PinnedColor] = []
    /// The Viewer's zoom when the app last quit or the Viewer closed.
    var viewerZoom: Double?

    // Settings › General
    var showsDockIcon = true
    var showsWindowsOnLaunch = true

    // Settings › Capture Area
    var frameColor = SettingsColor.blue
    /// 1 or 2 points.
    var frameLineWidth: Double = 1
    var showsSizeAtRest = true
    var sizeUnits = SizeUnits.pointsAndPixels

    // Settings › Viewer
    var viewerBackground = ViewerBackground.dark
    /// The pixel grid shows from this zoom on (docs/product.md, Pixel grid: 800% by default).
    var gridMinimumZoom: Double = 8
    var gridLines = GridLines.auto
    var crosshairColor = SettingsColor.orange
    /// Off: a mouse wheel zooms without ⌘. Trackpad scrolling always pans.
    var wheelZoomNeedsCommand = true

    // Settings › Screenshots
    /// Off by default (docs/product.md, Pixel grid).
    var gridInCopyView = false
    var fileNameStyle = FileNameStyle.macOS
    var revealsSavedFile = false

    // Settings › Shortcuts
    var shortcuts = Shortcuts()

    init() {}

    /// A key that is missing or unreadable (saved by an older or a newer version) keeps its default;
    /// the other settings load as saved.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        captureArea = c.value(.captureArea, or: d.captureArea)
        captureAreaPinned = c.value(.captureAreaPinned, or: d.captureAreaPinned)
        viewerAlwaysOnTop = c.value(.viewerAlwaysOnTop, or: d.viewerAlwaysOnTop)
        screenshotDirectory = c.value(.screenshotDirectory, or: d.screenshotDirectory)
        gridEnabled = c.value(.gridEnabled, or: d.gridEnabled)
        crosshairEnabled = c.value(.crosshairEnabled, or: d.crosshairEnabled)
        meterVisible = c.value(.meterVisible, or: d.meterVisible)
        referencesVisible = c.value(.referencesVisible, or: d.referencesVisible)
        expandedSidePanel = c.value(.expandedSidePanel, or: d.expandedSidePanel)
        sidePanelWidth = c.value(.sidePanelWidth, or: d.sidePanelWidth)
        pinnedColors = c.value(.pinnedColors, or: d.pinnedColors)
        viewerZoom = c.value(.viewerZoom, or: d.viewerZoom)
        showsDockIcon = c.value(.showsDockIcon, or: d.showsDockIcon)
        showsWindowsOnLaunch = c.value(.showsWindowsOnLaunch, or: d.showsWindowsOnLaunch)
        frameColor = c.value(.frameColor, or: d.frameColor)
        frameLineWidth = c.value(.frameLineWidth, or: d.frameLineWidth)
        showsSizeAtRest = c.value(.showsSizeAtRest, or: d.showsSizeAtRest)
        sizeUnits = c.value(.sizeUnits, or: d.sizeUnits)
        viewerBackground = c.value(.viewerBackground, or: d.viewerBackground)
        gridMinimumZoom = c.value(.gridMinimumZoom, or: d.gridMinimumZoom)
        gridLines = c.value(.gridLines, or: d.gridLines)
        crosshairColor = c.value(.crosshairColor, or: d.crosshairColor)
        wheelZoomNeedsCommand = c.value(.wheelZoomNeedsCommand, or: d.wheelZoomNeedsCommand)
        gridInCopyView = c.value(.gridInCopyView, or: d.gridInCopyView)
        fileNameStyle = c.value(.fileNameStyle, or: d.fileNameStyle)
        revealsSavedFile = c.value(.revealsSavedFile, or: d.revealsSavedFile)
        shortcuts = c.value(.shortcuts, or: d.shortcuts)
    }
}

/// An sRGB colour picked in Settings.
struct SettingsColor: Codable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// From 8-bit components.
    init(_ red: Int, _ green: Int, _ blue: Int) {
        self.init(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
    }

    init(_ color: NSColor) {
        let srgb = color.usingColorSpace(.sRGB) ?? .black
        self.init(red: Double(srgb.redComponent), green: Double(srgb.greenComponent), blue: Double(srgb.blueComponent))
    }

    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }

    /// WCAG contrast ratio, 1...21.
    func contrastRatio(with other: SettingsColor) -> Double {
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        func sample(_ color: SettingsColor) -> ColorSample {
            func byte(_ value: Double) -> UInt8 { UInt8((min(max(value, 0), 1) * 255).rounded()) }
            return ColorSample(
                red: byte(color.red), green: byte(color.green), blue: byte(color.blue), colorSpace: sRGB)
        }
        return ColorSample.contrastRatio(sample(self), sample(other))
    }

    static let blue = SettingsColor(10, 132, 255)
    static let orange = SettingsColor(255, 107, 0)
    static let amber = SettingsColor(255, 159, 10)
    static let pink = SettingsColor(255, 55, 95)
    static let green = SettingsColor(48, 209, 88)
    static let purple = SettingsColor(191, 90, 242)
    static let white = SettingsColor(255, 255, 255)
}

/// A panel at the right of the Viewer.
enum SidePanel: String, Codable, Sendable {
    case colorMeter, references

    /// The side panel column's width in points. At the narrowest the panels' content has scale 1.
    static let widthRange: ClosedRange<CGFloat> = 250...320
}

/// What the Viewer shows around the image and where nothing is captured.
enum ViewerBackground: String, Codable, CaseIterable, Sendable {
    case dark, light, checkerboard
}

/// How saved screenshots are named.
enum FileNameStyle: String, Codable, CaseIterable, Sendable {
    /// `Screen Loupe View 2026-09-24 at 14.20.05`, like macOS screenshots.
    case macOS
    /// `ScreenLoupe-View-20260924-142005`.
    case compact
}

@MainActor
@Observable
final class SettingsStore {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key = "settings"
    @ObservationIgnored private var observers: [(_ old: Settings, _ new: Settings) -> Void] = []

    private(set) var settings: Settings

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key), let decoded = try? JSONDecoder().decode(Settings.self, from: data) {
            settings = decoded
        } else {
            settings = Settings()
        }
    }

    func update(_ change: (inout Settings) -> Void) {
        var next = settings
        change(&next)
        guard next != settings else { return }
        let old = settings
        settings = next
        if let data = try? JSONEncoder().encode(next) {
            defaults.set(data, forKey: key)
        }
        for observer in observers {
            observer(old, next)
        }
    }

    /// Calls `observer` after every change, with the settings before and after it.
    func observe(_ observer: @escaping (_ old: Settings, _ new: Settings) -> Void) {
        observers.append(observer)
    }
}
