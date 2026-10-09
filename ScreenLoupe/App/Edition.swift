/// Which build this is, and what it adds to the core. The core calls into what an edition adds only
/// through this type; this one adds nothing.
enum Edition {
    /// Shown in About.
    static let name = "Built from source"

    /// Called once, when the windows are built: what the edition adds to them.
    @MainActor static func install(in windows: WindowManager) {}
}
