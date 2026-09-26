import CoreGraphics
import Foundation
import Testing

private let minimum = CGSize(width: 64, height: 64)

private func fitted(_ fit: StudioSizeFit) -> CGRect? {
    if case .fits(let rect) = fit { return rect }
    return nil
}

// MARK: - Applying a size

struct StudioSizeApplyTests {
    /// A MacBook-like 2× display, the primary.
    private let retina = DisplayInfo(id: 1, globalFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), scale: 2)
    private let plain = DisplayInfo(id: 2, globalFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080), scale: 1)
    /// 1440 × 900 pt at 2×: exactly 2880 × 1800 px.
    private let exact = DisplayInfo(id: 3, globalFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2)
    /// Left of the primary, reaching above it.
    private let left = DisplayInfo(id: 4, globalFrame: CGRect(x: -1920, y: -200, width: 1920, height: 1200), scale: 1)
    /// Above and left of the primary, 2×.
    private let aboveLeft = DisplayInfo(
        id: 5, globalFrame: CGRect(x: -1440, y: 900, width: 1440, height: 900), scale: 2)

    private func apply(_ rect: CGRect, _ width: Int, _ height: Int, on display: DisplayInfo) -> StudioSizeFit {
        StudioSizes.frame(rect, resizedTo: PixelSize(width: width, height: height), on: display, minimumSize: minimum)
    }

    @Test func retinaSizeIsHalfAsManyPointsKeepingTheTopLeftCorner() {
        let fit = apply(CGRect(x: 100, y: 200, width: 400, height: 300), 1280, 800, on: retina)
        #expect(fitted(fit) == CGRect(x: 100, y: 100, width: 640, height: 400))
    }

    @Test func oddPixelsOnRetinaAreHalfPoints() {
        let rect = fitted(apply(CGRect(x: 100, y: 200, width: 400, height: 300), 1201, 631, on: retina))
        #expect(rect?.size == CGSize(width: 600.5, height: 315.5))
        #expect(rect?.origin == CGPoint(x: 100, y: 184.5))
    }

    @Test func oneXSizeIsOnePointPerPixel() {
        let fit = apply(CGRect(x: 10, y: 900, width: 100, height: 100), 1200, 630, on: plain)
        #expect(fitted(fit) == CGRect(x: 10, y: 370, width: 1200, height: 630))
    }

    @Test func aFrameThatStaysOnTheDisplayDoesntMove() {
        let fit = apply(CGRect(x: 0, y: 500, width: 100, height: 100), 1000, 600, on: plain)
        #expect(fitted(fit) == CGRect(x: 0, y: 0, width: 1000, height: 600))
    }

    @Test func movesBackLeftAndUpAsLittleAsNeeded() {
        // Grows right and down past the display's right and bottom edges.
        let fit = apply(CGRect(x: 1000, y: 300, width: 200, height: 200), 1440, 900, on: plain)
        #expect(fitted(fit) == CGRect(x: 480, y: 0, width: 1440, height: 900))
    }

    @Test func movesBackRightAndDownAsLittleAsNeeded() {
        // Stuck out left and above before the size.
        let fit = apply(CGRect(x: -50, y: 1000, width: 200, height: 200), 300, 300, on: plain)
        #expect(fitted(fit) == CGRect(x: 0, y: 780, width: 300, height: 300))
    }

    @Test func exactlyTheDisplaysSizeFillsIt() {
        #expect(
            fitted(apply(CGRect(x: 300, y: 200, width: 200, height: 200), 1920, 1080, on: plain)) == plain.globalFrame)
        #expect(
            fitted(apply(CGRect(x: 300, y: 200, width: 200, height: 200), 2880, 1800, on: exact)) == exact.globalFrame)
    }

    @Test(arguments: [(2881, 1800), (2880, 1801), (2882, 1800), (5760, 3600)])
    func onePixelOverTheDisplayIsRefusedOnRetina(width: Int, height: Int) {
        #expect(apply(CGRect(x: 300, y: 200, width: 200, height: 200), width, height, on: exact) == .largerThanDisplay)
    }

    @Test(arguments: [(1921, 1080), (1920, 1081), (2880, 1800)])
    func overTheDisplayIsRefusedOnOneX(width: Int, height: Int) {
        #expect(apply(CGRect(x: 300, y: 200, width: 200, height: 200), width, height, on: plain) == .largerThanDisplay)
    }

    @Test func theSamePixelsFitOnRetinaButNotOnOneX() {
        let frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        #expect(fitted(apply(frame, 2560, 1600, on: retina)) != nil)
        #expect(apply(frame, 2560, 1600, on: plain) == .largerThanDisplay)
    }

    @Test func onADisplayLeftOfThePrimaryWithNegativeCoordinates() {
        // Top-left at (-100, 900): too far right for 1000 pt, so it moves left to the display's edge (0).
        let fit = apply(CGRect(x: -100, y: 800, width: 100, height: 100), 1000, 500, on: left)
        #expect(fitted(fit) == CGRect(x: -1000, y: 400, width: 1000, height: 500))
        // Below the display's bottom (-200): up just enough.
        let low = apply(CGRect(x: -1900, y: -150, width: 100, height: 100), 400, 300, on: left)
        #expect(fitted(low) == CGRect(x: -1900, y: -200, width: 400, height: 300))
        #expect(apply(CGRect(x: -1900, y: -150, width: 100, height: 100), 1920, 1201, on: left) == .largerThanDisplay)
    }

    @Test func onADisplayAboveAndLeftOfThePrimary() {
        let fit = apply(CGRect(x: -300, y: 1500, width: 100, height: 100), 1440, 900, on: aboveLeft)
        // 720 × 450 pt; moved left so its right edge meets the display's, its top kept.
        #expect(fitted(fit) == CGRect(x: -720, y: 1150, width: 720, height: 450))
        #expect(
            fitted(apply(CGRect(x: -300, y: 1500, width: 100, height: 100), 2880, 1800, on: aboveLeft))
                == aboveLeft.globalFrame)
    }

    @Test func exactlyTheMinimumFits() {
        let frame = CGRect(x: 100, y: 200, width: 400, height: 300)
        #expect(fitted(apply(frame, 128, 128, on: retina))?.size == minimum)
        #expect(fitted(apply(frame, 64, 64, on: plain))?.size == minimum)
    }

    @Test(arguments: [(127, 128), (128, 127), (1, 1), (100, 1800)])
    func underTheMinimumIsRefusedOnRetina(width: Int, height: Int) {
        #expect(
            apply(CGRect(x: 100, y: 200, width: 400, height: 300), width, height, on: retina) == .smallerThanMinimum)
    }

    @Test func underTheMinimumIsRefusedOnOneX() {
        let frame = CGRect(x: 100, y: 200, width: 400, height: 300)
        #expect(apply(frame, 63, 64, on: plain) == .smallerThanMinimum)
        #expect(apply(frame, 64, 63, on: plain) == .smallerThanMinimum)
        // 100 px is 100 pt on 1×, but 50 pt on 2×.
        #expect(fitted(apply(frame, 100, 100, on: plain)) != nil)
        #expect(apply(frame, 100, 100, on: retina) == .smallerThanMinimum)
    }

    @Test func tooLargeOnOneSideAndTooSmallOnTheOtherIsLarger() {
        #expect(apply(CGRect(x: 0, y: 0, width: 100, height: 100), 16384, 10, on: plain) == .largerThanDisplay)
    }
}

// MARK: - Titles, parsing, checkmarks

struct StudioSizeTextTests {
    @Test func titles() {
        #expect(StudioSizes.title(PixelSize(width: 1280, height: 800)) == "1280 × 800 px")
        #expect(StudioSizes.title(CustomSize(name: "Hero", width: 1600, height: 1000)) == "Hero · 1600 × 1000 px")
        #expect(StudioSizes.title(CustomSize(name: " Hero ", width: 1600, height: 1000)) == "Hero · 1600 × 1000 px")
        #expect(StudioSizes.title(CustomSize(name: "  ", width: 1600, height: 1000)) == "1600 × 1000 px")
        #expect(StudioSizes.title(CustomSize(width: 1600, height: 1000)) == "1600 × 1000 px")
    }

    @Test func validityLimits() {
        #expect(StudioSizes.isValid(width: 1, height: 1))
        #expect(StudioSizes.isValid(width: 16384, height: 16384))
        #expect(!StudioSizes.isValid(width: 0, height: 100))
        #expect(!StudioSizes.isValid(width: 100, height: 0))
        #expect(!StudioSizes.isValid(width: -5, height: 100))
        #expect(!StudioSizes.isValid(width: 16385, height: 100))
        #expect(!StudioSizes.isValid(width: 100, height: 16385))
    }

    @Test func parsingTypedSizes() {
        #expect(StudioSizes.parse(width: "1600", height: "1000") == PixelSize(width: 1600, height: 1000))
        #expect(StudioSizes.parse(width: " 1600 ", height: "1000 ") == PixelSize(width: 1600, height: 1000))
        #expect(StudioSizes.parse(width: "16384", height: "1") == PixelSize(width: 16384, height: 1))
        #expect(StudioSizes.parse(width: "", height: "1000") == nil)
        #expect(StudioSizes.parse(width: "1600", height: "") == nil)
        #expect(StudioSizes.parse(width: "1600.5", height: "1000") == nil)
        #expect(StudioSizes.parse(width: "abc", height: "1000") == nil)
        #expect(StudioSizes.parse(width: "0", height: "1000") == nil)
        #expect(StudioSizes.parse(width: "-1", height: "1000") == nil)
        #expect(StudioSizes.parse(width: "16385", height: "1000") == nil)
        #expect(StudioSizes.parse(width: "1 600", height: "1000") == nil)
    }

    @Test func presets() {
        for size in StudioSizes.appStore + StudioSizes.web {
            #expect(StudioSizes.isPreset(size))
        }
        #expect(!StudioSizes.isPreset(PixelSize(width: 1080, height: 1920)))
        #expect(StudioSizes.appStore.count == 4)
        #expect(StudioSizes.web.count == 2)
    }

    @Test func aPresetEntryIsCheckedAtItsSize() {
        let size = PixelSize(width: 1440, height: 900)
        #expect(StudioSizes.isChecked(size, isPresetEntry: true, current: size))
        #expect(!StudioSizes.isChecked(size, isPresetEntry: true, current: PixelSize(width: 1440, height: 901)))
        #expect(!StudioSizes.isChecked(size, isPresetEntry: true, current: nil))
    }

    @Test func aCustomSizeEqualToAPresetIsCheckedOnlyAsThePreset() {
        let size = PixelSize(width: 1920, height: 1080)
        #expect(StudioSizes.isChecked(size, isPresetEntry: true, current: size))
        #expect(!StudioSizes.isChecked(size, isPresetEntry: false, current: size))
    }

    @Test func aCustomSizeOfItsOwnIsChecked() {
        let size = PixelSize(width: 1600, height: 1000)
        #expect(StudioSizes.isChecked(size, isPresetEntry: false, current: size))
        #expect(!StudioSizes.isChecked(size, isPresetEntry: false, current: PixelSize(width: 1000, height: 1600)))
    }
}

// MARK: - Custom slots

struct CustomSizeSlotTests {
    private func size(_ width: Int) -> CustomSize { CustomSize(width: width, height: 100) }
    private var full: [CustomSize] { [size(1), size(2), size(3), size(4)] }

    /// Four slots, the filled ones first and the empty ones at the bottom.
    private func expectSlotInvariant(_ sizes: [CustomSize]) {
        let slots = StudioSizes.slots(sizes)
        #expect(slots.count == StudioSizes.slotCount)
        if let firstEmpty = slots.firstIndex(of: nil) {
            #expect(slots[firstEmpty...].allSatisfy { $0 == nil })
        }
    }

    @Test func slotsAreFilledFirstThenEmpty() {
        #expect(StudioSizes.slots([]) == [nil, nil, nil, nil])
        #expect(StudioSizes.slots([size(1), size(2)]) == [size(1), size(2), nil, nil])
        #expect(StudioSizes.slots(full) == full.map { $0 })
    }

    @Test func savedSizesDropInvalidOnesAndKeepFour() {
        let saved = [
            size(1), CustomSize(width: 0, height: 5), size(2), CustomSize(width: 5, height: 16385), size(3), size(4),
            size(5),
        ]
        #expect(StudioSizes.sanitized(saved) == full)
    }

    @Test func fillingTakesTheFirstEmptySlot() {
        var sizes: [CustomSize] = []
        for width in 1...4 {
            sizes = StudioSizes.adding(size(width), to: sizes)
            expectSlotInvariant(sizes)
        }
        #expect(sizes == full)
        // Full: a fifth is not taken.
        #expect(StudioSizes.adding(size(5), to: full) == full)
    }

    @Test func fillingRejectsInvalidSizes() {
        #expect(StudioSizes.adding(CustomSize(width: 0, height: 5), to: [size(1)]) == [size(1)])
        #expect(StudioSizes.adding(CustomSize(width: 16385, height: 5), to: [size(1)]) == [size(1)])
        #expect(
            StudioSizes.adding(CustomSize(width: 16384, height: 1), to: []) == [CustomSize(width: 16384, height: 1)])
    }

    @Test(arguments: 0..<4)
    func editingASlotKeepsItsPlace(index: Int) {
        var expected = full
        expected[index] = CustomSize(name: "Edited", width: 9, height: 9)
        #expect(StudioSizes.replacing(at: index, with: expected[index], in: full) == expected)
    }

    @Test func editingRejectsInvalidSizesAndEmptySlots() {
        let sizes = [size(1), size(2)]
        #expect(StudioSizes.replacing(at: 1, with: CustomSize(width: 0, height: 5), in: sizes) == sizes)
        #expect(StudioSizes.replacing(at: 2, with: size(9), in: sizes) == sizes)
        #expect(StudioSizes.replacing(at: -1, with: size(9), in: sizes) == sizes)
    }

    @Test(arguments: 0..<4)
    func removingMovesTheRestUpAndLeavesTheEmptySlotAtTheBottom(index: Int) {
        let sizes = StudioSizes.removing(at: index, from: full)
        var expected = full
        expected.remove(at: index)
        #expect(sizes == expected)
        #expect(StudioSizes.slots(sizes).last == .some(nil))
        expectSlotInvariant(sizes)
    }

    @Test func removingAnEmptyOrMissingSlotChangesNothing() {
        let sizes = [size(1), size(2)]
        #expect(StudioSizes.removing(at: 2, from: sizes) == sizes)
        #expect(StudioSizes.removing(at: 3, from: sizes) == sizes)
        #expect(StudioSizes.removing(at: -1, from: sizes) == sizes)
    }

    @Test func removingTheLastLeavesAllEmpty() {
        #expect(StudioSizes.slots(StudioSizes.removing(at: 0, from: [size(1)])) == [nil, nil, nil, nil])
    }

    @Test(arguments: [
        // (source, gap, result) with three filled slots 1, 2, 3.
        (0, 0, [1, 2, 3]), (0, 1, [1, 2, 3]), (0, 2, [2, 1, 3]), (0, 3, [2, 3, 1]),
        (1, 0, [2, 1, 3]), (1, 3, [1, 3, 2]), (2, 0, [3, 1, 2]), (2, 1, [1, 3, 2]), (2, 3, [1, 2, 3]),
    ])
    func movingReordersFilledSlots(source: Int, gap: Int, result: [Int]) {
        let sizes = [size(1), size(2), size(3)]
        let moved = StudioSizes.moving(from: source, to: gap, in: sizes)
        #expect(moved == result.map(size))
        expectSlotInvariant(moved)
    }

    @Test func invalidMovesKeepTheOrderOrStopAtTheFilledOnes() {
        let sizes = [size(1), size(2), size(3)]
        // Dropped among or past the empty slots: last of the filled ones.
        #expect(StudioSizes.moving(from: 0, to: 4, in: sizes) == [size(2), size(3), size(1)])
        #expect(StudioSizes.moving(from: 0, to: 99, in: sizes) == [size(2), size(3), size(1)])
        #expect(StudioSizes.moving(from: 2, to: -3, in: sizes) == [size(3), size(1), size(2)])
        // An empty slot, or none, doesn't move.
        #expect(StudioSizes.moving(from: 3, to: 0, in: sizes) == sizes)
        #expect(StudioSizes.moving(from: -1, to: 0, in: sizes) == sizes)
        #expect(StudioSizes.moving(from: 0, to: 2, in: []) == [])
    }

    @Test func rowIdentitiesMoveLikeTheirSizes() {
        let ids = ["a", "b", "c", "d"]
        // Three filled slots: "d" is the empty one and stays last.
        #expect(StudioSizes.moved(ids, from: 0, to: 4, within: 3) == ["b", "c", "a", "d"])
        #expect(StudioSizes.moved(ids, from: 2, to: 0, within: 3) == ["c", "a", "b", "d"])
        #expect(StudioSizes.moved(ids, from: 3, to: 0, within: 3) == ids)
        // A removed slot's identity goes to the bottom, with the empty slot.
        #expect(StudioSizes.moved(ids, from: 1, to: 4, within: 4) == ["a", "c", "d", "b"])
    }

    @Test func identitiesAndSizesStayPairedThroughEveryMove() {
        let sizes = [size(1), size(2), size(3)]
        let ids = [1, 2, 3, 0]
        for source in -1...4 {
            for gap in -1...5 {
                let movedSizes = StudioSizes.moving(from: source, to: gap, in: sizes)
                let movedIDs = StudioSizes.moved(ids, from: source, to: gap, within: sizes.count)
                #expect(movedSizes.map(\.width) == Array(movedIDs.prefix(3)))
                #expect(movedIDs.last == 0)
            }
        }
    }
}

// MARK: - Decoding saved sizes

struct CustomSizeDecodingTests {
    private struct Saved: Decodable {
        var sizes: [CustomSize]
        enum CodingKeys: String, CodingKey { case sizes }
        init(from decoder: Decoder) throws {
            sizes = try decoder.container(keyedBy: CodingKeys.self).customSizes(.sizes)
        }
    }

    private func decode(_ json: String) throws -> [CustomSize] {
        try JSONDecoder().decode(Saved.self, from: Data(json.utf8)).sizes
    }

    @Test func roundTrip() throws {
        let sizes = [CustomSize(name: "Hero", width: 1600, height: 1000), CustomSize(width: 800, height: 600)]
        let data = try JSONEncoder().encode(["sizes": sizes])
        #expect(try JSONDecoder().decode(Saved.self, from: data).sizes == sizes)
    }

    @Test func aSizeWithoutANameStillLoads() throws {
        #expect(try decode(#"{"sizes": [{"width": 1600, "height": 1000}]}"#) == [CustomSize(width: 1600, height: 1000)])
    }

    @Test func aMissingKeyOrAnotherTypeIsNoSizes() throws {
        #expect(try decode("{}") == [])
        #expect(try decode(#"{"sizes": "big"}"#) == [])
    }

    @Test func aBadElementCostsOnlyItself() throws {
        let json =
            #"{"sizes": [{"width": 1}, {"width": 1600, "height": 1000}, 7, {"width": 0, "height": 5}, {"width": 800, "height": "x"}, {"name": "B", "width": 640, "height": 480}]}"#
        #expect(
            try decode(json) == [CustomSize(width: 1600, height: 1000), CustomSize(name: "B", width: 640, height: 480)])
    }

    @Test func moreThanFourKeepTheFirstFour() throws {
        let json =
            #"{"sizes": [{"width": 1, "height": 1}, {"width": 2, "height": 2}, {"width": 3, "height": 3}, {"width": 4, "height": 4}, {"width": 5, "height": 5}]}"#
        #expect(try decode(json).map(\.width) == [1, 2, 3, 4])
    }
}

// MARK: - Aspect Lock

struct AspectLockTests {
    @Test func cornerKeepsTheOppositeCornerAndFollowsTheLongerSide() {
        // Dragged the bottom-right corner: the top-left (100, 700) stays.
        let dragged = CGRect(x: 100, y: 300, width: 800, height: 400)
        let rect = AspectLock.resized(dragged, handle: .bottomRight, ratio: 16.0 / 10, scale: 1, minimumSize: minimum)
        #expect(rect == CGRect(x: 100, y: 200, width: 800, height: 500))
        // The height leads when it is the longer side in the ratio.
        let tall = CGRect(x: 100, y: 100, width: 400, height: 600)
        let fitted = AspectLock.resized(tall, handle: .bottomRight, ratio: 16.0 / 10, scale: 1, minimumSize: minimum)
        #expect(fitted == CGRect(x: 100, y: 100, width: 960, height: 600))
    }

    @Test func topLeftCornerKeepsTheBottomRight() {
        let dragged = CGRect(x: 200, y: 100, width: 800, height: 400)
        let rect = AspectLock.resized(dragged, handle: .topLeft, ratio: 16.0 / 10, scale: 1, minimumSize: minimum)
        #expect(rect == CGRect(x: 200, y: 100, width: 800, height: 500))
    }

    @Test func sideKeepsItsLengthAndCentresTheOtherSides() {
        // The right edge dragged: width leads, height changes around the middle (y 500).
        let dragged = CGRect(x: 0, y: 400, width: 320, height: 200)
        let rect = AspectLock.resized(dragged, handle: .right, ratio: 2, scale: 1, minimumSize: minimum)
        #expect(rect == CGRect(x: 0, y: 420, width: 320, height: 160))
        // The top edge dragged: height leads, width around the middle (x 160).
        let top = AspectLock.resized(dragged, handle: .top, ratio: 2, scale: 1, minimumSize: minimum)
        #expect(top == CGRect(x: -40, y: 400, width: 400, height: 200))
    }

    @Test func sideOnRetinaCentresTheOtherAxisOnTheHalfPointGrid() {
        // 301 px wide at 1:1 is 301 px high; its middle can't sit on the old one (y 150), so it goes
        // to the nearest half point.
        let dragged = CGRect(x: 10, y: 100, width: 150.5, height: 100)
        for handle in [OverlayHandle.left, .right] {
            let rect = AspectLock.resized(dragged, handle: handle, ratio: 1, scale: 2, minimumSize: minimum)
            #expect(rect.size == CGSize(width: 150.5, height: 150.5))
            #expect(rect.minY == CGFloat(75))
            #expect(abs(rect.midY - 150) <= 0.25)
        }
        // Top and bottom: the width's middle (x 85.25) the same way.
        let tall = CGRect(x: 10, y: 100, width: 150.5, height: 100.5)
        for handle in [OverlayHandle.top, .bottom] {
            let rect = AspectLock.resized(tall, handle: handle, ratio: 1, scale: 2, minimumSize: minimum)
            #expect(rect.size == CGSize(width: 100.5, height: 100.5))
            #expect(rect.minX * 2 == (rect.minX * 2).rounded())
            #expect(abs(rect.midX - tall.midX) <= 0.25)
        }
    }

    @Test func retinaSideRoundsTheOtherSideToWholePixels() {
        let dragged = CGRect(x: 10, y: 10, width: 150.5, height: 90)
        let rect = AspectLock.resized(dragged, handle: .right, ratio: 16.0 / 9, scale: 2, minimumSize: minimum)
        // 301 px wide, 169 px high (169.3).
        #expect(rect.size == CGSize(width: 150.5, height: 84.5))
        #expect(rect.minX == CGFloat(10))
    }

    @Test func keepsTheMinimumOnBothSides() {
        let dragged = CGRect(x: 0, y: 0, width: 64, height: 64)
        let wide = AspectLock.resized(dragged, handle: .bottomRight, ratio: 4, scale: 1, minimumSize: minimum)
        #expect(wide.size == CGSize(width: 256, height: 64))
        let tall = AspectLock.resized(dragged, handle: .right, ratio: 0.5, scale: 1, minimumSize: minimum)
        #expect(tall.size == CGSize(width: 64, height: 128))
    }

    @Test func leadIsTheSideSnappingMoved() {
        let resized = CGRect(x: 100, y: 100, width: 403, height: 247)
        // ⌘ snapped the right edge: the width moved.
        #expect(AspectLock.lead(resized: resized, snapped: CGRect(x: 100, y: 100, width: 400, height: 247)) == .width)
        // Snapped the bottom edge: the height moved (and the origin with it).
        #expect(AspectLock.lead(resized: resized, snapped: CGRect(x: 100, y: 102, width: 403, height: 245)) == .height)
        // Nothing snapped, or both sides did.
        #expect(AspectLock.lead(resized: resized, snapped: resized) == .longer)
        #expect(AspectLock.lead(resized: resized, snapped: CGRect(x: 100, y: 100, width: 400, height: 250)) == .longer)
    }

    @Test func aSnappedWidthLeadsACorner() {
        // Height is the longer side in the ratio (250 × 1.6 = 400 > 380), but the width snapped.
        let snapped = CGRect(x: 100, y: 50, width: 380, height: 250)
        let rect = AspectLock.resized(
            snapped, handle: .bottomRight, ratio: 1.6, scale: 1, minimumSize: minimum, lead: .width)
        #expect(rect == CGRect(x: 100, y: 62, width: 380, height: 238))
        #expect(rect.maxX == snapped.maxX)
    }

    @Test func aSnappedHeightLeadsACorner() {
        // Width is the longer side (480 > 200 × 1.6), but the height snapped: the bottom stays on it.
        let snapped = CGRect(x: 100, y: 100, width: 480, height: 200)
        let rect = AspectLock.resized(
            snapped, handle: .bottomRight, ratio: 1.6, scale: 2, minimumSize: minimum, lead: .height)
        #expect(rect == CGRect(x: 100, y: 100, width: 320, height: 200))
        #expect(rect.minY == snapped.minY)
    }

    @Test func withoutASnapTheLongerSideLeadsACorner() {
        let dragged = CGRect(x: 100, y: 100, width: 480, height: 200)
        #expect(
            AspectLock.resized(dragged, handle: .bottomRight, ratio: 1.6, scale: 1, minimumSize: minimum, lead: .longer)
                == AspectLock.resized(dragged, handle: .bottomRight, ratio: 1.6, scale: 1, minimumSize: minimum))
        #expect(
            AspectLock.resized(dragged, handle: .topLeft, ratio: 1.6, scale: 1, minimumSize: minimum).size
                == CGSize(width: 480, height: 300))
    }

    @Test func leadDoesntChangeASide() {
        let dragged = CGRect(x: 0, y: 400, width: 320, height: 200)
        for lead in [AspectLock.Lead.width, .height, .longer] {
            #expect(
                AspectLock.resized(dragged, handle: .right, ratio: 2, scale: 1, minimumSize: minimum, lead: lead)
                    == CGRect(x: 0, y: 420, width: 320, height: 160))
        }
    }

    @Test func negativeCoordinates() {
        let dragged = CGRect(x: -1000, y: -500, width: 300, height: 100)
        let rect = AspectLock.resized(dragged, handle: .bottomLeft, ratio: 1, scale: 2, minimumSize: minimum)
        #expect(rect == CGRect(x: -1000, y: -700, width: 300, height: 300))
    }

    /// Every handle, 1× and 2×, growing, shrinking and shrinking past the minimum, from a 16:10 frame
    /// on the grid: whole pixels, the ratio to within a pixel, the minimum, and what stays in place.
    @Test(
        arguments: OverlayHandle.allCases, [CGFloat(1), 2])
    func everyHandleKeepsTheRatioOnTheGrid(handle: OverlayHandle, scale: CGFloat) {
        let start = CGRect(x: -600, y: 100, width: 400, height: 250)
        let ratio: CGFloat = 1.6
        for delta in [
            CGVector(dx: 37.5, dy: -21), CGVector(dx: -80.5, dy: 55), CGVector(dx: -2000, dy: 2000),
            CGVector(dx: 2000, dy: -2000),
        ] {
            // The drag's delta, in the direction that grows or shrinks for this handle.
            let resized = CaptureAreaEditing.resized(start, handle: handle, by: delta)
            let rect = AspectLock.resized(resized, handle: handle, ratio: ratio, scale: scale, minimumSize: minimum)
            let width = rect.width * scale
            let height = rect.height * scale
            #expect(width == width.rounded() && height == height.rounded())
            #expect(abs(width / ratio - height) <= 0.5)
            #expect(rect.width >= minimum.width && rect.height >= minimum.height)
            for edge in [rect.minX, rect.maxX, rect.minY, rect.maxY] {
                #expect(edge * scale == (edge * scale).rounded())
            }
            // What stays: the opposite edges, or the middle of the other axis within half a pixel.
            if handle.movesMinX { #expect(rect.maxX == start.maxX) }
            if handle.movesMaxX { #expect(rect.minX == start.minX) }
            if handle.movesMinY { #expect(rect.maxY == start.maxY) }
            if handle.movesMaxY { #expect(rect.minY == start.minY) }
            if !handle.movesMinX && !handle.movesMaxX { #expect(abs(rect.midX - start.midX) <= 0.5 / scale) }
            if !handle.movesMinY && !handle.movesMaxY { #expect(abs(rect.midY - start.midY) <= 0.5 / scale) }
        }
    }

    @Test(arguments: OverlayHandle.allCases)
    func shrinkingFarStopsAtTheMinimum(handle: OverlayHandle) {
        let start = CGRect(x: 0, y: 0, width: 400, height: 200)
        let resized = CaptureAreaEditing.resized(start, handle: handle, by: CGVector(dx: 0, dy: 0))
        let squashed = CGRect(
            x: handle.movesMinX ? resized.maxX - 1 : resized.minX,
            y: handle.movesMinY ? resized.maxY - 1 : resized.minY,
            width: handle.movesMinX || handle.movesMaxX ? 1 : resized.width,
            height: handle.movesMinY || handle.movesMaxY ? 1 : resized.height)
        let rect = AspectLock.resized(squashed, handle: handle, ratio: 2, scale: 2, minimumSize: minimum)
        #expect(rect.height >= minimum.height)
        #expect(rect.width >= minimum.width)
        #expect(rect.width == rect.height * 2)
    }
}

struct ResizeRuleTests {
    private let corners: [OverlayHandle] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
    private let sides: [OverlayHandle] = [.top, .left, .right, .bottom]

    @Test func shiftOnACornerSquaresWithOrWithoutTheLock() {
        for handle in corners {
            #expect(ResizeRule.forDrag(of: handle, shift: true, aspectRatio: 1.6) == .square)
            #expect(ResizeRule.forDrag(of: handle, shift: true, aspectRatio: nil) == .square)
        }
    }

    @Test func shiftOnASideLeavesTheLockOrNothing() {
        for handle in sides {
            #expect(ResizeRule.forDrag(of: handle, shift: true, aspectRatio: 1.6) == .aspect(1.6))
            #expect(ResizeRule.forDrag(of: handle, shift: true, aspectRatio: nil) == .free)
        }
    }

    @Test func withoutShiftTheLockDecides() {
        for handle in OverlayHandle.allCases {
            #expect(ResizeRule.forDrag(of: handle, shift: false, aspectRatio: 0.75) == .aspect(0.75))
            #expect(ResizeRule.forDrag(of: handle, shift: false, aspectRatio: nil) == .free)
        }
    }
}
