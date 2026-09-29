import AppKit
import Observation

/// State kept between launches (docs/product.md, Kept between launches) and the choices made in the Settings window. The
/// Viewer frame is kept by AppKit through its autosave name; everything else lives here.
struct Settings: Codable, Equatable {
    /// Capture Area in AppKit global coordinates.
    var captureArea: CGRect?
    /// The lock chosen with the pin's ▾, and whether the pin has it on.
    var captureAreaLock = CaptureAreaLock.pinned
    var captureAreaLocked = false
    /// The viewport handle mode: the outline of the part the Viewer shows stays on the Capture Area
    /// with a handle that pans the Viewer.
    var showsViewportHandle = false
    /// The Capture Area's margins as last set, and the colour and opacity of their band. Whether the
    /// margins are on isn't kept: the magnet they need comes up off.
    var captureAreaMargins = CaptureMargins()
    var marginsColor = SettingsColor.green
    /// 0...1.
    var marginsOpacity = 0.2
    /// Keep the Viewer above the windows of other apps.
    var viewerAlwaysOnTop = false
    /// The Screenshot studio's frame in AppKit global coordinates, and its palette's origin.
    var studioFrame: CGRect?
    var studioPaletteOrigin: CGPoint?
    /// The studio's sizes of the user's own, in slot order: at most four, all valid.
    var studioCustomSizes: [CustomSize] = []
    /// Aspect Lock, and the width-to-height ratio it keeps, taken when it is turned on or a size is
    /// applied while it is on.
    var studioAspectLocked = false
    var studioAspectRatio: Double = 16.0 / 10
    /// What is laid under studio pictures.
    var studioBackground = StudioBackground.screen
    /// Whether a One Window picture keeps the window's shadow.
    var studioWindowShadow = true
    /// How long Capture, Copy and Save wait before taking the picture.
    var studioDelay = StudioDelay.off
    /// Whether studio pictures, but One Window's, include the pointer.
    var studioIncludesPointer = false
    /// The format, colour space and scale of studio pictures.
    var studioOutput = StudioOutput()
    /// Where screenshots are saved; the Desktop when unset.
    var screenshotDirectory: String?
    /// Viewer overlays and the Color Meter panel.
    var gridEnabled = false
    /// Whether the pointer shows in the Viewer, drawn as `pointerStyle` says.
    var crosshairEnabled = true
    var pointerStyle = PointerStyle.crosshair
    var meterVisible = false
    /// References and Recent Captures take turns in the side column: at most one is open.
    var referencesVisible = false
    var capturesVisible = false
    /// With two side panels open, the one that is expanded.
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
        captureAreaLock = c.value(.captureAreaLock, or: d.captureAreaLock)
        captureAreaLocked = (try? CaptureAreaLock.SavedPin(from: decoder))?.isOn ?? d.captureAreaLocked
        showsViewportHandle = c.value(.showsViewportHandle, or: d.showsViewportHandle)
        captureAreaMargins = c.value(.captureAreaMargins, or: d.captureAreaMargins)
        marginsColor = c.value(.marginsColor, or: d.marginsColor)
        marginsOpacity = min(max(c.value(.marginsOpacity, or: d.marginsOpacity), 0), 1)
        viewerAlwaysOnTop = c.value(.viewerAlwaysOnTop, or: d.viewerAlwaysOnTop)
        studioFrame = c.value(.studioFrame, or: d.studioFrame)
        studioPaletteOrigin = c.value(.studioPaletteOrigin, or: d.studioPaletteOrigin)
        studioCustomSizes = c.customSizes(.studioCustomSizes)
        studioAspectLocked = c.value(.studioAspectLocked, or: d.studioAspectLocked)
        let ratio = c.value(.studioAspectRatio, or: d.studioAspectRatio)
        studioAspectRatio = ratio.isFinite && ratio > 0 ? ratio : d.studioAspectRatio
        studioBackground = c.studioBackground(.studioBackground)
        studioWindowShadow = c.value(.studioWindowShadow, or: d.studioWindowShadow)
        studioDelay = c.value(.studioDelay, or: d.studioDelay)
        studioIncludesPointer = c.value(.studioIncludesPointer, or: d.studioIncludesPointer)
        studioOutput = c.value(.studioOutput, or: d.studioOutput)
        screenshotDirectory = c.value(.screenshotDirectory, or: d.screenshotDirectory)
        gridEnabled = c.value(.gridEnabled, or: d.gridEnabled)
        crosshairEnabled = c.value(.crosshairEnabled, or: d.crosshairEnabled)
        pointerStyle = c.value(.pointerStyle, or: d.pointerStyle)
        meterVisible = c.value(.meterVisible, or: d.meterVisible)
        referencesVisible = c.value(.referencesVisible, or: d.referencesVisible)
        capturesVisible = c.value(.capturesVisible, or: d.capturesVisible) && !referencesVisible
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

    /// The lock that holds the Capture Area now, or `nil` while the pin is off.
    var activeCaptureAreaLock: CaptureAreaLock? { captureAreaLocked ? captureAreaLock : nil }

    /// The ratio the studio's frame keeps while it is resized, or `nil` while Aspect Lock is off.
    var activeStudioAspectRatio: Double? { studioAspectLocked ? studioAspectRatio : nil }
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
    static let gray = SettingsColor(142, 142, 147)
    static let white = SettingsColor(255, 255, 255)
    /// The Screenshot studio's frame, apart from every Capture Area preset.
    static let studio = SettingsColor(240, 127, 26)
}

/// A panel at the right of the Viewer.
enum SidePanel: String, Codable, Sendable {
    case colorMeter, references, captures

    /// The side panel column's width in points. At the narrowest the panels' content has scale 1.
    static let widthRange: ClosedRange<CGFloat> = 250...320
}

/// How the pointer inside the Capture Area shows in the Viewer (docs/product.md, Crosshair and
/// cursor).
enum PointerStyle: String, Codable, CaseIterable, Sendable {
    /// Lines through the pixel pointed at, drawn over the image.
    case crosshair
    /// An arrow drawn over the image at its usual size, tip on the pixel.
    case cursor
    /// The real pointer, recorded by the capture into its pixels.
    case capturedCursor
}

/// What the Viewer shows around the image and where nothing is captured.
enum ViewerBackground: String, Codable, CaseIterable, Sendable {
    case dark, light, checkerboard
}

/// The pixel grid's line colour (Settings › Viewer). Auto draws dark lines over light pixels and
/// light lines over dark ones.
enum GridLines: String, Codable, CaseIterable, Sendable {
    case auto, dark, light
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

    /// Calls `apply` with the value at `keyPath` now, and again after every change that changes it.
    /// A subscriber that depends on several settings together observes a computed property that
    /// returns them as one `Equatable` value.
    func observe<Value: Equatable>(_ keyPath: KeyPath<Settings, Value>, _ apply: @escaping (Value) -> Void) {
        apply(settings[keyPath: keyPath])
        observers.append { [weak self] old, new in
            guard let self, old[keyPath: keyPath] != new[keyPath: keyPath] else { return }
            // The current value: an observer before this one may have changed the settings again.
            apply(settings[keyPath: keyPath])
        }
    }
}
