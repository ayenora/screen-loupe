import CoreGraphics
import Foundation

/// While the magnet moves the Capture Area with its window, the Viewer holds the frame it showed
/// (docs/product.md, Capture Area): the stream takes each new source rect a moment after the area
/// moved, so the live frames would land a pixel off one way or the other, which at a high zoom is
/// a jump of many points. The held frame shows the window's content where it is, since the area
/// moved with the window. The hold ends once the window has been still for `settle` and a frame of
/// the area where it is now has come in, so no frame from before the stream caught up shows; with
/// no such frame (nothing on screen changed) it holds on. Anything that takes the live view's place
/// or changes what it captures ends it at once.
struct MagnetHold {
    /// How long the window stays still before the hold can end.
    static let settle: TimeInterval = 0.15

    /// What happens during a hold.
    enum Event: Equatable, Sendable {
        /// A live frame came in, or the settle time passed, at `time`; `showsArea`: the latest live
        /// frame shows the area where it is (`frameShows`).
        case check(at: TimeInterval, showsArea: Bool)
        /// The area changed, not by the magnet: to `rect`.
        case areaChanged(to: CGRect)
        case frozen
        case recentCaptureShown
        case viewerClosed
        /// The magnet turned off or let go of its window.
        case magnetStopped
        case displaysChanged
        /// The stream stopped or broke, or the Screen Recording access changed.
        case captureInterrupted
    }

    /// When the magnet last moved the area, in seconds of any one clock.
    private(set) var lastMove: TimeInterval
    /// Where the magnet last put the area.
    private(set) var area: CGRect

    init(movedTo area: CGRect, at time: TimeInterval) {
        lastMove = time
        self.area = area
    }

    /// The magnet moved the area again.
    mutating func moved(to area: CGRect, at time: TimeInterval) {
        lastMove = time
        self.area = area
    }

    /// Whether `event` ends the hold. A check ends it once the window has been still for `settle`
    /// and the latest frame shows the area. A change of the area ends it when the change moved or
    /// resized it (the user's handle, Fit to Window); one that leaves it where the magnet put it
    /// (the tab's text) doesn't. Every other event ends it.
    func ends(on event: Event) -> Bool {
        switch event {
        case .check(let time, let showsArea):
            return showsArea && time - lastMove >= Self.settle
        case .areaChanged(let rect):
            return rect != area
        case .frozen, .recentCaptureShown, .viewerClosed, .magnetStopped, .displaysChanged, .captureInterrupted:
            return true
        }
    }

    /// How long after `time` the window will have been still for `settle`, when a frame that came
    /// in before then can end the hold; `nil` once it has.
    func untilSettled(at time: TimeInterval) -> TimeInterval? {
        let still = time - lastMove
        return still < Self.settle ? Self.settle - still : nil
    }

    /// Whether the latest live frame shows `area`, the area where it is now: captured with its
    /// geometry, after the stream took that geometry on (`isCaptured(at:afterConfiguringAt:)`).
    static func frameShows(
        _ area: CaptureGeometry?, frameGeometry: CaptureGeometry?, capturedAfterConfiguring: Bool
    ) -> Bool {
        guard let area else { return false }
        return frameGeometry == area && capturedAfterConfiguring
    }

    /// Whether a frame captured at `capturedAt` came after the stream took on the geometry it is
    /// stored with, at `configuredAt` (host time, as `SCStreamFrameInfo.displayTime`). A frame
    /// captured before still has the old source rect, the same size and the new geometry's label;
    /// without either time it can't be told apart, so it doesn't count.
    static func isCaptured(at capturedAt: UInt64?, afterConfiguringAt configuredAt: UInt64?) -> Bool {
        guard let capturedAt, let configuredAt else { return false }
        return capturedAt >= configuredAt
    }

    /// Where the outline of the part the Viewer shows is placed during a hold: on the area where it
    /// is, whose window the held picture shows, while the area is on the held frame's display; `nil`
    /// on another display, whose pixels are of another size than the held frame's.
    static func viewedPartGeometry(area: CaptureGeometry?, held: CaptureGeometry?) -> CaptureGeometry? {
        guard let area, let held, area.display == held.display else { return nil }
        return area
    }
}
