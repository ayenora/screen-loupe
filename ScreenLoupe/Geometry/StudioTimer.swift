import CoreGraphics
import Foundation

/// How long the Screenshot studio waits before Capture, Copy or Save take the picture
/// (docs/product.md, Screenshot studio). Saved as its seconds; a value only another version knows
/// decodes as off.
enum StudioDelay: Int, Codable, CaseIterable, Sendable {
    case off = 0
    case three = 3
    case five = 5
    case ten = 10

    /// In the Timer list and Screenshot › Delay.
    var title: String { self == .off ? "Off" : "\(rawValue) s" }
}

/// What a press of Capture, Copy or Save asks for.
enum StudioShot: Equatable, Sendable {
    /// Copy, then the save panel.
    case capture
    case copy
    /// The save panel.
    case save

    /// Said in the countdown: "Copying in 3 s".
    var verb: String {
        switch self {
        case .capture: "Capturing"
        case .copy: "Copying"
        case .save: "Saving"
        }
    }
}

/// The studio's countdown before a picture (docs/design.md, Screenshot studio): idle, or counting
/// down to one shot. Times are seconds on a monotonic clock.
enum StudioCountdown: Equatable, Sendable {
    case idle
    case counting(StudioShot, start: TimeInterval, total: TimeInterval)

    enum Event: Equatable, Sendable {
        /// Capture, Copy or Save pressed, with the delay set at that moment, whether a picture can
        /// be taken now (`StudioShotCheck`), and whether one of the studio's window pickers runs.
        case press(StudioShot, delay: StudioDelay, check: StudioShotCheck, pickerRunning: Bool, at: TimeInterval)
        /// The countdown's clock, and whether the frame is on a display.
        case tick(at: TimeInterval, frameOnDisplay: Bool)
        /// The studio was hidden.
        case hidden
        /// A window picker started: the studio's One Window or Fit to Window, or one of the Capture
        /// Area's. It takes the mouse and the keyboard, which a countdown must not have to share.
        case pickerStarted
    }

    enum Outcome: Equatable, Sendable {
        case none
        /// No delay: the shot is taken now, as without a timer.
        case shootNow(StudioShot)
        /// The shot can't be taken now: it is refused at once, as without a timer, not after the
        /// wait.
        case refusedNow(StudioShot)
        /// Counting; `stopsPicker`: the running window picker stops first, so it doesn't hold the
        /// mouse meanwhile.
        case started(stopsPicker: Bool)
        case cancelled
        /// The frame went off every display: the countdown stops, saying so.
        case frameOffDisplay
        /// The countdown reached zero: the shot is taken now.
        case fire(StudioShot)
    }

    /// The countdown after `event`, and what to do. Any press during a countdown cancels it and
    /// starts nothing, whichever button it is and without a check, and so do hiding the studio and
    /// starting a window picker; the countdown keeps the delay it started with.
    func after(_ event: Event) -> (StudioCountdown, Outcome) {
        switch (self, event) {
        case (.idle, .press(let shot, let delay, let check, let pickerRunning, let now)):
            if delay == .off {
                (.idle, .shootNow(shot))
            } else if check != .take {
                (.idle, .refusedNow(shot))
            } else {
                (
                    .counting(shot, start: now, total: TimeInterval(delay.rawValue)),
                    .started(stopsPicker: pickerRunning)
                )
            }
        case (.counting, .press), (.counting, .hidden), (.counting, .pickerStarted):
            (.idle, .cancelled)
        case (.counting, .tick(_, frameOnDisplay: false)):
            (.idle, .frameOffDisplay)
        case (.counting(let shot, let start, let total), .tick(let now, _)):
            now >= start + total ? (.idle, .fire(shot)) : (self, .none)
        default:
            (self, .none)
        }
    }

    var isCounting: Bool { self != .idle }

    /// Whole seconds left at `now`, rounded up, so the count reads 3, 2, 1 and fires at zero; 0 when
    /// idle.
    func secondsLeft(at now: TimeInterval) -> Int {
        guard case .counting(_, let start, let total) = self else { return 0 }
        return max(0, Int((start + total - now).rounded(.up)))
    }

    /// How much of the countdown is left at `now`, 1 at its start and 0 at its end; the ring shows it.
    func fractionLeft(at now: TimeInterval) -> Double {
        guard case .counting(_, let start, let total) = self, total > 0 else { return 0 }
        return min(max((start + total - now) / total, 0), 1)
    }

    /// "Copying in 3 s". No Escape: the app can't see it without Accessibility, and taking it as a
    /// hot key would stop it closing the menu the timer is there to catch.
    func text(at now: TimeInterval) -> String {
        guard case .counting(let shot, _, _) = self else { return "" }
        return "\(shot.verb) in \(secondsLeft(at: now)) s"
    }

    /// Where the countdown shows, in AppKit global points: where the frame's notice does — left of
    /// the tab and its button (`tab`), or right of them when the display (`screen`) has no room on
    /// the left — centred on the tab's row and kept on the display.
    static func pillRect(size: CGSize, tab: CGRect, screen: CGRect, gap: CGFloat = 4, margin: CGFloat = 6) -> CGRect {
        var x = tab.minX - gap - size.width
        if x < screen.minX + margin { x = tab.maxX + gap }
        x = min(max(x, screen.minX + margin), screen.maxX - margin - size.width)
        let y = min(max(tab.midY - size.height / 2, screen.minY + margin), screen.maxY - margin - size.height)
        return CGRect(origin: CGPoint(x: x.rounded(), y: y.rounded()), size: size)
    }
}

/// Whether a studio picture can be taken now, checked when a button is pressed and again when a
/// countdown fires, so a picture is refused on what holds at the moment it would be taken.
enum StudioShotCheck: Equatable, Sendable {
    /// The studio is hidden, or a picture is on its way.
    case ignore
    /// A save panel is open: it comes forward instead, one panel at a time and none in the picture.
    case bringSavePanelForward
    case needsPermission
    /// "Frame is not wholly on one display".
    case notOnOneDisplay
    case take

    init(visible: Bool, capturing: Bool, savePanelOpen: Bool, permitted: Bool, onOneDisplay: Bool) {
        self =
            if !visible || capturing {
                .ignore
            } else if savePanelOpen {
                .bringSavePanelForward
            } else if !permitted {
                .needsPermission
            } else if !onOneDisplay {
                .notOnOneDisplay
            } else {
                .take
            }
    }
}
