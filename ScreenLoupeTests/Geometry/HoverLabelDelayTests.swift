import Foundation
import Testing

struct HoverLabelDelayTests {
    @Test func neverShownWaitsTheRest() {
        #expect(HoverLabelDelay.delay(at: 100, lastHidden: nil) == HoverLabelDelay.rest)
    }

    /// A click forgets the last name (`lastHidden` is `nil`), so the next button waits too, even
    /// right after.
    @Test func afterAClickWaitsTheRest() {
        #expect(HoverLabelDelay.delay(at: 0, lastHidden: nil) == HoverLabelDelay.rest)
    }

    /// From a named button straight onto the next one: its name went the same moment.
    @Test func nextButtonRightAwayShowsAtOnce() {
        #expect(HoverLabelDelay.delay(at: 100, lastHidden: 100) == 0)
    }

    /// Across the gap between two groups.
    @Test func withinTheGraceShowsAtOnce() {
        #expect(HoverLabelDelay.delay(at: 100.2, lastHidden: 100) == 0)
    }

    @Test func exactlyAtTheGraceLimitShowsAtOnce() {
        #expect(HoverLabelDelay.delay(at: 100 + HoverLabelDelay.grace, lastHidden: 100) == 0)
    }

    @Test func justPastTheGraceWaitsTheRest() {
        #expect(HoverLabelDelay.delay(at: 100 + HoverLabelDelay.grace + 0.001, lastHidden: 100) == HoverLabelDelay.rest)
    }

    @Test func longAfterWaitsTheRest() {
        #expect(HoverLabelDelay.delay(at: 200, lastHidden: 100) == HoverLabelDelay.rest)
    }
}
