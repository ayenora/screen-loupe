import Foundation

/// Which build this is, and what it adds to the core. The core calls into what an edition adds only
/// through this type; this one adds nothing.
enum Edition {
    /// Shown in About.
    static let name = "Built from source"

    /// Called once, when the windows are built: what the edition adds to them.
    @MainActor static func install(in windows: WindowManager) {}

    /// Called once, when the Color Meter panel is built: what the edition adds to it and to how its
    /// colours are read (`ColorMeterPanel.formats`, `addToTitle`, `addBelowSwatch`, `colorNote`,
    /// `PixelInspector.reader`).
    @MainActor static func install(in meter: ColorMeterPanel) {}

    /// Files the system asks the app to open, once launching has finished: what the edition does
    /// with them. `windows` builds the windows if they aren't yet; this edition opens nothing and
    /// leaves them unbuilt.
    @MainActor static func open(_ urls: [URL], in windows: @autoclosure () -> WindowManager) {}
}
