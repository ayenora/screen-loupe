import CoreGraphics

/// The arrangement of all connected displays.
///
/// The primary display is the one whose global frame starts at the origin; both the AppKit and the
/// Quartz global systems are anchored to it.
struct DisplayLayout: Equatable, Sendable {
    let displays: [DisplayInfo]
    let primary: DisplayInfo

    /// Returns `nil` when no display sits at the global origin, which a real layout always has.
    init?(displays: [DisplayInfo]) {
        guard let primary = displays.first(where: { $0.globalFrame.origin == .zero }) else { return nil }
        self.displays = displays
        self.primary = primary
    }

    func display(withID id: CGDirectDisplayID) -> DisplayInfo? {
        displays.first { $0.id == id }
    }
}
