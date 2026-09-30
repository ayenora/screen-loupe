import CoreGraphics
import Foundation
import Testing

struct SnapshotFrameTests {
    @Test func theLiveViewTakesTheLatestFrame() {
        #expect(RecentCaptureRules.snapshotFrame(frozen: nil, held: nil, live: "live") == "live")
    }

    @Test func aFrozenViewTakesTheFrozenFrame() {
        #expect(RecentCaptureRules.snapshotFrame(frozen: "frozen", held: nil, live: "live") == "frozen")
    }

    /// While the magnet moves the area the live view shows the held frame; the latest may not show
    /// the area yet.
    @Test func aHoldTakesTheHeldFrame() {
        #expect(RecentCaptureRules.snapshotFrame(frozen: nil, held: "held", live: "live") == "held")
    }

    @Test func frozenComesBeforeHeld() {
        #expect(RecentCaptureRules.snapshotFrame(frozen: "frozen", held: "held", live: "live") == "frozen")
    }

    @Test func aFrozenFrameIsTakenAlsoWithoutALiveOne() {
        #expect(RecentCaptureRules.snapshotFrame(frozen: "frozen", held: nil, live: nil) == "frozen")
    }

    @Test func noFrameTakesNothing() {
        #expect(RecentCaptureRules.snapshotFrame(frozen: String?.none, held: nil, live: nil) == nil)
    }
}

struct SnapshotViewTests {
    @Test func onTheLiveViewTheCurrentZoomAndPan() {
        #expect(RecentCaptureRules.snapshotView(savedLive: nil, current: "current") == "current")
    }

    /// With a row shown, the current zoom and pan are the row's.
    @Test func withARowShownTheLiveViewsPutAway() {
        #expect(RecentCaptureRules.snapshotView(savedLive: "live", current: "row") == "live")
    }
}

struct RecentCaptureListTests {
    private func adding(_ item: Int, to items: [Int], shown: Int? = nil) -> [Int] {
        RecentCaptureRules.adding(item, to: items) { $0 == shown }
    }

    @Test func theLimitIsEight() {
        #expect(RecentCaptureRules.limit == 8)
    }

    @Test func theFirstGoesOnItsOwn() {
        #expect(adding(1, to: []) == [1])
    }

    @Test func theNewestGoesOnTop() {
        #expect(adding(3, to: [2, 1]) == [3, 2, 1])
    }

    @Test func belowTheLimitNothingGoes() {
        #expect(adding(8, to: [7, 6, 5, 4, 3, 2, 1]) == [8, 7, 6, 5, 4, 3, 2, 1])
    }

    @Test func theNinthDropsTheOldest() {
        #expect(adding(9, to: [8, 7, 6, 5, 4, 3, 2, 1]) == [9, 8, 7, 6, 5, 4, 3, 2])
    }

    @Test func theShownOldestStaysAndTheNextOldestGoes() {
        #expect(adding(9, to: [8, 7, 6, 5, 4, 3, 2, 1], shown: 1) == [9, 8, 7, 6, 5, 4, 3, 1])
    }

    @Test func aShownRowInTheMiddleLeavesTheOldestToGo() {
        #expect(adding(9, to: [8, 7, 6, 5, 4, 3, 2, 1], shown: 5) == [9, 8, 7, 6, 5, 4, 3, 2])
    }

    @Test func theNewestShownStillDropsTheOldest() {
        #expect(adding(9, to: [8, 7, 6, 5, 4, 3, 2, 1], shown: 9) == [9, 8, 7, 6, 5, 4, 3, 2])
    }
}

struct LinkedCaptureTests {
    private typealias View = RecentCaptureRules.CaptureView
    private typealias Link = RecentCaptureRules.Link<Int>

    private static let small = PixelSize(width: 294, height: 239)
    private static let large = PixelSize(width: 1920, height: 1080)
    private let fitted = View(zoom: nil, offset: .zero)
    private let corner = View(zoom: 8, offset: CGPoint(x: -800, y: -400))
    private let whole = View(zoom: 1, offset: CGPoint(x: 173, y: 120))

    private func link(_ id: Int, size: PixelSize = small, linked: Bool = false, view: View? = nil) -> Link {
        Link(id: id, size: size, isLinked: linked, view: view ?? View(zoom: 2, offset: CGPoint(x: id, y: id)))
    }

    private func view(of id: Int, in links: [Link]) -> View? { links.first { $0.id == id }?.view }

    // MARK: Who can be linked

    @Test func theFirstCanBeLinkedWhateverItsSize() {
        #expect(RecentCaptureRules.canLink(1, in: [link(1)]))
        #expect(RecentCaptureRules.canLink(1, in: [link(1, size: Self.large), link(2)]))
    }

    @Test func theSameSizeCanJoin() {
        #expect(RecentCaptureRules.canLink(3, in: [link(1, linked: true), link(2, linked: true), link(3)]))
    }

    @Test func anotherSizeCannotJoin() {
        #expect(!RecentCaptureRules.canLink(2, in: [link(1, linked: true), link(2, size: Self.large)]))
    }

    /// Width and height both count: a rotated size is another.
    @Test func swappedSidesAreAnotherSize() {
        let rotated = PixelSize(width: 239, height: 294)
        #expect(!RecentCaptureRules.canLink(2, in: [link(1, linked: true), link(2, size: rotated)]))
    }

    @Test func oneSideDifferingIsAnotherSize() {
        for size in [PixelSize(width: 294, height: 240), PixelSize(width: 295, height: 239)] {
            #expect(!RecentCaptureRules.canLink(2, in: [link(1, linked: true), link(2, size: size)]))
        }
    }

    @Test func aLinkedOneCanAlwaysBeUnlinked() {
        #expect(RecentCaptureRules.canLink(1, in: [link(1, linked: true)]))
    }

    @Test func anUnknownCaptureCannotBeLinked() {
        #expect(!RecentCaptureRules.canLink(9, in: [link(1)]))
    }

    /// Unlinking the last one leaves none linked: another size can be linked again.
    @Test func afterTheLastIsUnlinkedAnotherSizeCanBeLinked() {
        let links = [link(1, linked: true), link(2, size: Self.large)]
        let unlinked = RecentCaptureRules.unlinking(1, shown: nil, viewer: corner, in: links)
        #expect(RecentCaptureRules.canLink(2, in: unlinked))
    }

    /// A deleted or pushed-out capture is gone from the list, and so from the group: once the only
    /// linked one goes, another size can be linked; while one of the size is left, it can't.
    @Test func aRemovedLinkedOneNoLongerHoldsTheSize() {
        let links = [link(1, linked: true), link(2, linked: true), link(3, size: Self.large)]
        #expect(!RecentCaptureRules.canLink(3, in: links.filter { $0.id != 1 }))
        #expect(RecentCaptureRules.canLink(3, in: links.filter { $0.id != 1 && $0.id != 2 }))
    }

    // MARK: Leaving a capture

    @Test func anUnlinkedOneKeepsItsViewToItself() {
        let links = [link(1), link(2, linked: true), link(3, linked: true)]
        #expect(RecentCaptureRules.leaving(1, at: corner, in: links) == [link(1, view: corner), links[1], links[2]])
    }

    @Test func aLinkedOneAloneKeepsItToItself() {
        let links = [link(1, linked: true), link(2)]
        #expect(RecentCaptureRules.leaving(1, at: corner, in: links) == [link(1, linked: true, view: corner), link(2)])
    }

    @Test func aLinkedOneWritesItToEveryLinkedOneOnly() {
        let links = [link(1, linked: true), link(2), link(3, linked: true)]
        #expect(
            RecentCaptureRules.leaving(3, at: corner, in: links) == [
                link(1, linked: true, view: corner), link(2), link(3, linked: true, view: corner),
            ])
    }

    @Test func leavingAnUnknownOneChangesNothing() {
        let links = [link(1, linked: true), link(2)]
        #expect(RecentCaptureRules.leaving(9, at: corner, in: links) == links)
    }

    // MARK: Linking

    @Test func theFirstLinkedKeepsItsOwnView() {
        let result = RecentCaptureRules.linking(1, shown: nil, viewer: corner, in: [link(1, view: whole), link(2)])
        #expect(result == .init(links: [link(1, linked: true, view: whole), link(2)], showsNewView: false))
    }

    /// Shown and linked first: the Viewer already shows its view.
    @Test func theFirstLinkedWhileShownDoesNotMove() {
        let result = RecentCaptureRules.linking(1, shown: 1, viewer: corner, in: [link(1, view: whole)])
        #expect(result == .init(links: [link(1, linked: true, view: whole)], showsNewView: false))
    }

    @Test func withNoLinkedOneShownItTakesTheKeptView() {
        let links = [link(1, linked: true, view: corner), link(2, view: whole), link(3)]
        let result = RecentCaptureRules.linking(2, shown: 3, viewer: fitted, in: links)
        #expect(result?.links == [links[0], link(2, linked: true, view: corner), links[2]])
        #expect(result?.showsNewView == false)
    }

    /// The linked one shown may have moved since the group's view was kept: the Viewer's is taken.
    @Test func withALinkedOneShownItTakesTheViewersView() {
        let links = [link(1, linked: true, view: whole), link(2)]
        let result = RecentCaptureRules.linking(2, shown: 1, viewer: corner, in: links)
        #expect(result?.links == [links[0], link(2, linked: true, view: corner)])
        #expect(result?.showsNewView == false)
    }

    @Test func linkingTheShownOneMovesTheViewerToTheGroupsView() {
        let links = [link(1, linked: true, view: corner), link(2, view: whole)]
        let result = RecentCaptureRules.linking(2, shown: 2, viewer: whole, in: links)
        #expect(result == .init(links: [links[0], link(2, linked: true, view: corner)], showsNewView: true))
    }

    @Test func linkingTheShownOneAtTheGroupsViewDoesNotMove() {
        let links = [link(1, linked: true, view: corner), link(2, view: corner)]
        #expect(RecentCaptureRules.linking(2, shown: 2, viewer: corner, in: links)?.showsNewView == false)
    }

    /// Its kept view is from when it was last put away; the Viewer may have moved since.
    @Test func linkingTheShownOneMovesTheViewerEvenWhenItsKeptViewIsTheGroups() {
        let links = [link(1, linked: true, view: corner), link(2, view: corner)]
        let result = RecentCaptureRules.linking(2, shown: 2, viewer: whole, in: links)
        #expect(result == .init(links: [links[0], link(2, linked: true, view: corner)], showsNewView: true))
    }

    @Test func anotherSizeIsNotLinked() {
        let links = [link(1, linked: true), link(2, size: Self.large)]
        #expect(RecentCaptureRules.linking(2, shown: nil, viewer: corner, in: links) == nil)
    }

    @Test func aLinkedOneIsNotLinkedAgain() {
        #expect(RecentCaptureRules.linking(1, shown: nil, viewer: corner, in: [link(1, linked: true)]) == nil)
    }

    /// An image file linked before it was ever put away keeps no zoom: fitted is the group's view.
    @Test func aFittedFilesViewIsTakenAsItIs() {
        let links = [link(1, linked: true, view: fitted), link(2, view: corner)]
        let result = RecentCaptureRules.linking(2, shown: 2, viewer: corner, in: links)
        #expect(result == .init(links: [links[0], link(2, linked: true, view: fitted)], showsNewView: true))
    }

    /// A file shown fitted and linked first keeps being fitted.
    @Test func aFittedFileLinkedFirstStaysFitted() {
        let result = RecentCaptureRules.linking(1, shown: 1, viewer: whole, in: [link(1, view: fitted)])
        #expect(result?.links == [link(1, linked: true, view: fitted)])
        #expect(result?.showsNewView == false)
    }

    // MARK: Unlinking

    /// The group already keeps its view while another capture, or live, shows.
    @Test func unlinkingOneNotShownKeepsEveryView() {
        let links = [link(1, linked: true, view: whole), link(2, linked: true, view: whole)]
        #expect(
            RecentCaptureRules.unlinking(1, shown: 2, viewer: corner, in: links) == [
                link(1, view: whole), links[1],
            ])
        #expect(RecentCaptureRules.unlinking(1, shown: nil, viewer: corner, in: links)[0] == link(1, view: whole))
    }

    /// The shown one may have moved since the group's view was kept: the group keeps what shows,
    /// and so does it, as its own.
    @Test func unlinkingTheShownOneLeavesTheViewersViewWithTheGroup() {
        let links = [link(1, linked: true, view: whole), link(2, linked: true, view: whole), link(3)]
        #expect(
            RecentCaptureRules.unlinking(2, shown: 2, viewer: corner, in: links) == [
                link(1, linked: true, view: corner), link(2, view: corner), links[2],
            ])
    }

    @Test func unlinkingTheShownLastOneKeepsTheViewersView() {
        #expect(
            RecentCaptureRules.unlinking(1, shown: 1, viewer: corner, in: [link(1, linked: true, view: whole)]) == [
                link(1, view: corner)
            ])
    }

    @Test func unlinkingAnUnlinkedOneChangesNothing() {
        let links = [link(1, view: whole), link(2, linked: true)]
        #expect(RecentCaptureRules.unlinking(1, shown: 1, viewer: corner, in: links) == links)
    }

    // MARK: Flipping between linked captures

    /// Leaving A for B: B opens where A was left.
    @Test func switchingFromOneLinkedToAnotherShowsTheSameSpot() {
        let links = [link(1, linked: true, view: whole), link(2, linked: true, view: whole)]
        #expect(view(of: 2, in: RecentCaptureRules.leaving(1, at: corner, in: links)) == corner)
    }

    /// Live in between keeps nothing of a capture: B opens where A was left.
    @Test func throughLiveTheNextLinkedShowsTheSameSpot() {
        let links = [link(1, linked: true), link(2, linked: true)]
        let afterA = RecentCaptureRules.leaving(1, at: corner, in: links)
        #expect(view(of: 2, in: afterA) == corner)
    }

    /// An unlinked capture shown in between keeps its view to itself.
    @Test func throughAnUnlinkedOneTheNextLinkedShowsTheSameSpot() {
        let links = [link(1, linked: true), link(2, linked: true), link(3)]
        let afterA = RecentCaptureRules.leaving(1, at: corner, in: links)
        let afterC = RecentCaptureRules.leaving(3, at: whole, in: afterA)
        #expect(view(of: 2, in: afterC) == corner)
        #expect(view(of: 3, in: afterC) == whole)
    }

    /// Deleting the shown linked capture first goes to live, which puts it away: the others keep its view.
    @Test func deletingTheShownLinkedOneLeavesItsViewWithTheGroup() {
        let links = [link(1, linked: true), link(2, linked: true), link(3, linked: true)]
        let left = RecentCaptureRules.leaving(1, at: corner, in: links).filter { $0.id != 1 }
        #expect(left.map(\.view) == [corner, corner])
        #expect(left.map(\.isLinked) == [true, true])
    }

    /// A file shown fitted and left at its fitted zoom gives the group that zoom.
    @Test func leavingAFileGivesItsZoomToTheGroup() {
        let links = [link(1, linked: true, view: fitted), link(2, linked: true, view: fitted)]
        #expect(view(of: 2, in: RecentCaptureRules.leaving(1, at: whole, in: links)) == whole)
    }
}

struct RecentCaptureSizeTextTests {
    @Test func theSizeIsInPixels() {
        #expect(RecentCaptureRules.sizeText(PixelSize(width: 294, height: 239)) == "294 × 239 px")
    }

    /// As every size in the app: no thousands separators.
    @Test func largeSizesHaveNoSeparators() {
        #expect(RecentCaptureRules.sizeText(PixelSize(width: 4957, height: 3384)) == "4957 × 3384 px")
    }

    @Test func aSinglePixel() {
        #expect(RecentCaptureRules.sizeText(PixelSize(width: 1, height: 1)) == "1 × 1 px")
    }
}

struct RecentCaptureDateTextTests {
    private let utc = TimeZone(identifier: "UTC")!

    /// 12 July 2026, `hour`:32:05 UTC.
    private func july12(hour: Int = 14) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: DateComponents(year: 2026, month: 7, day: 12, hour: hour, minute: 32, second: 5))!
    }

    private func text(_ date: Date, _ locale: String, timeZone: TimeZone? = nil) -> String {
        RecentCaptureRules.dateFormatter(locale: Locale(identifier: locale), timeZone: timeZone ?? utc)
            .string(from: date)
    }

    /// Month first, and the 24-hour time although the US writes 12-hour.
    @Test func theUSWritesMonthFirstIn24Hours() {
        #expect(text(july12(), "en_US") == "7/12, 14:32:05")
    }

    @Test func theUKWritesDayFirst() {
        #expect(text(july12(), "en_GB") == "12/07, 14:32:05")
    }

    @Test func germanyWritesDotsAfterDayAndMonth() {
        #expect(text(july12(), "de_DE") == "12.7., 14:32:05")
    }

    @Test func russiaWritesDotsWithTwoDigitMonths() {
        #expect(text(july12(), "ru_RU") == "12.07, 14:32:05")
    }

    @Test func midnightIsZeroHours() {
        #expect(text(july12(hour: 0), "en_US") == "7/12, 00:32:05")
    }

    /// The instant in the given time zone: past midnight in Tokyo it is the next day.
    @Test func theTimeZoneMovesTheDayAndHour() {
        #expect(text(july12(hour: 20), "en_US", timeZone: TimeZone(identifier: "Asia/Tokyo")!) == "7/13, 05:32:05")
    }
}

struct SnapshotAreaTests {
    private func live(
        zoom: CGFloat, offset: CGPoint, content: CGSize = CGSize(width: 400, height: 300),
        viewport: CGSize = CGSize(width: 640, height: 480)
    ) -> ZoomPanState {
        ZoomPanState(zoom: zoom, offset: offset, contentSize: content, viewportSize: viewport)
    }

    private func area(_ state: ZoomPanState, selection: CGRect? = nil) -> CGRect? {
        RecentCaptureRules.snapshotArea(selection: selection, in: state)
    }

    // MARK: No selection: the part the Viewer shows

    @Test func aWholeImageInTheViewerKeepsAllOfIt() {
        let state = live(zoom: 1, offset: CGPoint(x: 173, y: 120), content: CGSize(width: 294, height: 240))
        #expect(area(state) == CGRect(x: 0, y: 0, width: 294, height: 240))
    }

    @Test func zoomedInKeepsJustTheVisiblePixels() {
        // At 800% the 640 × 480 viewport shows source 100…180 × 50…110.
        #expect(area(live(zoom: 8, offset: CGPoint(x: -800, y: -400))) == CGRect(x: 100, y: 50, width: 80, height: 60))
    }

    @Test func aPixelShowingInPartIsKept() {
        // Source 100.5…180.5 × 50.25…110.25: half pixels at every edge count.
        #expect(area(live(zoom: 8, offset: CGPoint(x: -804, y: -402))) == CGRect(x: 100, y: 50, width: 81, height: 61))
    }

    @Test func zoomedOutKeepsTheImageNotTheSpaceAroundIt() {
        let state = live(zoom: 0.5, offset: CGPoint(x: 220, y: 165))
        #expect(area(state) == CGRect(x: 0, y: 0, width: 400, height: 300))
    }

    @Test func zoomedOutAtAnOddScaleStillKeepsTheWholeImage() {
        // 12.5%: the 400 × 300 image is 50 × 37.5 viewport pixels.
        let state = live(zoom: 0.125, offset: CGPoint(x: 295, y: 221))
        #expect(area(state) == CGRect(x: 0, y: 0, width: 400, height: 300))
    }

    @Test func pannedPastTheTopLeftKeepsOnlyTheImagePart() {
        // Source -50…150 × 25…175 at 400%: nothing left of the image's edge is kept.
        let state = live(zoom: 4, offset: CGPoint(x: 200, y: -100), viewport: CGSize(width: 800, height: 600))
        #expect(area(state) == CGRect(x: 0, y: 25, width: 150, height: 150))
    }

    @Test func pannedPastTheBottomRightKeepsOnlyTheImagePart() {
        // Source 150…350 × 100…250 at 400% of a 300 × 200 image.
        let state = live(
            zoom: 4, offset: CGPoint(x: -600, y: -400), content: CGSize(width: 300, height: 200),
            viewport: CGSize(width: 800, height: 600))
        #expect(area(state) == CGRect(x: 150, y: 100, width: 150, height: 100))
    }

    @Test func aTwoTimesSourceKeepsItsBackingPixels() {
        // A 147 × 120 pt area at 2× is 294 × 240 px; at 200% a 294 × 480 viewport shows its right half.
        let state = live(
            zoom: 2, offset: CGPoint(x: -294, y: 0), content: CGSize(width: 294, height: 240),
            viewport: CGSize(width: 294, height: 480))
        #expect(area(state) == CGRect(x: 147, y: 0, width: 147, height: 240))
    }

    @Test func aOneTimesSourceAtTheSameZoomKeepsTheSameCount() {
        let state = live(
            zoom: 2, offset: CGPoint(x: -147, y: 0), content: CGSize(width: 147, height: 120),
            viewport: CGSize(width: 147, height: 240))
        #expect(area(state) == CGRect(x: 73, y: 0, width: 74, height: 120))
    }

    @Test func aFractionalZoomRoundsOutward() {
        // 150%: source 2…8.67 × 2…8.67.
        let state = live(zoom: 1.5, offset: CGPoint(x: -3, y: -3), viewport: CGSize(width: 10, height: 10))
        #expect(area(state) == CGRect(x: 2, y: 2, width: 7, height: 7))
    }

    /// 21 ÷ 0.7 comes out as 30.000000000000004: the edge is 30, not a pixel past it.
    @Test func aFloatStepPastAnEdgeAddsNoPixel() {
        let state = live(
            zoom: 0.7, offset: .zero, content: CGSize(width: 100, height: 100), viewport: CGSize(width: 21, height: 21))
        #expect(area(state) == CGRect(x: 0, y: 0, width: 30, height: 30))
    }

    /// 33 ÷ 1.1 comes out as 29.999999999999996: the edge is 30, not a pixel before it.
    @Test func aFloatStepBeforeAnEdgeAddsNoPixel() {
        let state = live(
            zoom: 1.1, offset: CGPoint(x: -33, y: -33), content: CGSize(width: 100, height: 100),
            viewport: CGSize(width: 11, height: 11))
        #expect(area(state) == CGRect(x: 30, y: 30, width: 10, height: 10))
    }

    @Test func atTheHighestZoomAPixelAndAPartOfOneAreKept() {
        // 6400%: source 100…101.5625 on both axes.
        let state = live(zoom: 64, offset: CGPoint(x: -6400, y: -6400), viewport: CGSize(width: 100, height: 100))
        #expect(area(state) == CGRect(x: 100, y: 100, width: 2, height: 2))
    }

    @Test func noViewportKeepsNothing() {
        #expect(area(live(zoom: 1, offset: .zero, viewport: .zero)) == nil)
    }

    @Test func noImageKeepsNothing() {
        #expect(area(live(zoom: 1, offset: .zero, content: .zero)) == nil)
    }

    // MARK: A selection: just the selection

    @Test func aSelectionInViewKeepsJustIt() {
        let state = live(zoom: 8, offset: CGPoint(x: -800, y: -400))
        let selection = CGRect(x: 110, y: 60, width: 12, height: 5)
        #expect(area(state, selection: selection) == selection)
    }

    @Test func aSelectionReachingPastTheViewerIsKeptWhole() {
        let state = live(zoom: 8, offset: CGPoint(x: -800, y: -400))
        let selection = CGRect(x: 90, y: 40, width: 200, height: 100)
        #expect(area(state, selection: selection) == selection)
    }

    @Test func aSelectionOutOfViewIsStillKept() {
        let state = live(zoom: 8, offset: CGPoint(x: -800, y: -400))
        let selection = CGRect(x: 0, y: 0, width: 20, height: 10)
        #expect(area(state, selection: selection) == selection)
    }

    @Test func aSelectionIsKeptWhateverTheZoom() {
        let selection = CGRect(x: 10, y: 20, width: 30, height: 40)
        #expect(area(live(zoom: 0.25, offset: CGPoint(x: 270, y: 202)), selection: selection) == selection)
        #expect(area(live(zoom: 1.5, offset: CGPoint(x: -3, y: -3)), selection: selection) == selection)
    }

    /// The area shrank under the selection: the part still inside is kept.
    @Test func aSelectionPastTheImageKeepsThePartInside() {
        let state = live(zoom: 1, offset: .zero)
        #expect(
            area(state, selection: CGRect(x: 380, y: 290, width: 50, height: 50))
                == CGRect(x: 380, y: 290, width: 20, height: 10))
    }

    /// Nothing of the selection is left in the image: there is no selection, and the view is kept.
    @Test func aSelectionWhollyOutsideTheImageKeepsTheView() {
        let state = live(zoom: 8, offset: CGPoint(x: -800, y: -400))
        #expect(
            area(state, selection: CGRect(x: 500, y: 0, width: 10, height: 10))
                == CGRect(x: 100, y: 50, width: 80, height: 60))
    }
}

struct SnapshotOffsetTests {
    @Test func aCropAtTheCornerOpensWhereItWas() {
        #expect(
            RecentCaptureRules.snapshotOffset(
                CGPoint(x: 173, y: 120), zoom: 1, area: CGRect(x: 0, y: 0, width: 294, height: 240))
                == CGPoint(x: 173, y: 120))
    }

    @Test func aZoomedInCropStartsWhereItsFirstPixelShowed() {
        // Pixel 100 showed half, at viewport x -4; pixel 50 a quarter, at y -2.
        #expect(
            RecentCaptureRules.snapshotOffset(
                CGPoint(x: -804, y: -402), zoom: 8, area: CGRect(x: 100, y: 50, width: 81, height: 61))
                == CGPoint(x: -4, y: -2))
    }

    @Test func aSelectionOpensWhereItShowed() {
        #expect(
            RecentCaptureRules.snapshotOffset(
                CGPoint(x: 16, y: 8), zoom: 8, area: CGRect(x: 3, y: 2, width: 12, height: 5))
                == CGPoint(x: 40, y: 24))
    }

    @Test func aFractionalZoom() {
        #expect(
            RecentCaptureRules.snapshotOffset(
                CGPoint(x: -3, y: -3), zoom: 1.5, area: CGRect(x: 2, y: 2, width: 7, height: 7))
                == CGPoint(x: 0, y: 0))
    }

    /// Every kept pixel lands where the live view showed it.
    @Test func theKeptPixelsShowAsLiveDid() {
        let live = ZoomPanState(
            zoom: 8, offset: CGPoint(x: -804, y: -402), contentSize: CGSize(width: 400, height: 300),
            viewportSize: CGSize(width: 640, height: 480))
        let area = RecentCaptureRules.snapshotArea(selection: nil, in: live)!
        let row = ZoomPanState(
            zoom: 8, offset: RecentCaptureRules.snapshotOffset(live.offset, zoom: 8, area: area),
            contentSize: area.size, viewportSize: live.viewportSize)
        for point in [CGPoint(x: 100, y: 50), CGPoint(x: 140.5, y: 77), CGPoint(x: 180, y: 110)] {
            #expect(
                row.viewportPoint(forSourcePoint: CGPoint(x: point.x - area.minX, y: point.y - area.minY))
                    == live.viewportPoint(forSourcePoint: point))
        }
        // Opening it clamps the pan, and moves nothing.
        #expect(row.clamped() == row)
    }

    /// A zoomed-out snapshot keeps the whole image, which opens where it showed.
    @Test func aZoomedOutSnapshotOpensUnmoved() {
        let live = ZoomPanState(
            zoom: 0.5, offset: CGPoint(x: 220, y: 165), contentSize: CGSize(width: 400, height: 300),
            viewportSize: CGSize(width: 640, height: 480))
        let area = RecentCaptureRules.snapshotArea(selection: nil, in: live)!
        let row = ZoomPanState(
            zoom: 0.5, offset: RecentCaptureRules.snapshotOffset(live.offset, zoom: 0.5, area: area),
            contentSize: area.size, viewportSize: live.viewportSize)
        #expect(row == live)
        #expect(row.clamped() == row)
    }
}
