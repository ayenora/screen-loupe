import CoreGraphics
import Testing

struct SuppliedAreaTests {
    private let display = DisplayInfo(id: 1, globalFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2)
    private var frozen: CaptureGeometry { .wholeDisplay(display) }
    private var supplied: CaptureGeometry {
        var geometry = CaptureGeometry.wholeDisplay(display)
        geometry.sourceRect.rect = CGRect(x: 100, y: 100, width: 200, height: 100)
        geometry.outputSize = PixelSize(width: 400, height: 200)
        geometry.areaSize = geometry.outputSize
        return geometry
    }

    @Test func theCaptureAreaWhileItShowsAndNothingIsSupplied() {
        #expect(SuppliedArea.pointerPlace(frozen: nil, supplied: nil, areaShown: true) == .captureArea)
    }

    @Test func nowhereWithTheAreaHiddenAndNothingSupplied() {
        #expect(SuppliedArea.pointerPlace(frozen: nil, supplied: nil, areaShown: false) == .none)
        #expect(SuppliedArea.pointerPlace(frozen: frozen, supplied: nil, areaShown: false) == .none)
    }

    @Test func theSuppliedAreaWhileItIsShownLive() {
        #expect(SuppliedArea.pointerPlace(frozen: nil, supplied: supplied, areaShown: false) == .geometry(supplied))
        #expect(SuppliedArea.pointerPlace(frozen: nil, supplied: supplied, areaShown: true) == .geometry(supplied))
    }

    /// The frozen picture is where the area was when it froze: turned on or off while frozen, or
    /// the Capture Area moved since, the pointer is placed in it.
    @Test func aFrozenFramesOwnPlaceWhateverIsSuppliedNow() {
        #expect(SuppliedArea.pointerPlace(frozen: frozen, supplied: supplied, areaShown: false) == .geometry(frozen))
        #expect(SuppliedArea.pointerPlace(frozen: frozen, supplied: nil, areaShown: true) == .geometry(frozen))
    }

    @Test func onlyTheLiveViewIsKeptCentred() {
        #expect(SuppliedArea.keepsCentered(centersLiveView: true, showsStill: false))
        #expect(!SuppliedArea.keepsCentered(centersLiveView: true, showsStill: true))
        #expect(!SuppliedArea.keepsCentered(centersLiveView: false, showsStill: false))
        #expect(!SuppliedArea.keepsCentered(centersLiveView: false, showsStill: true))
    }
}

struct ShortcutTargetTests {
    @Test func theAppsActionsComeFirst() {
        #expect(ShortcutRules.target(ofID: 0, actions: 7, added: 1) == .action(0))
        #expect(ShortcutRules.target(ofID: 6, actions: 7, added: 1) == .action(6))
    }

    @Test func addedShortcutsHaveIdsOfTheirOwn() {
        #expect(ShortcutRules.id(ofAdded: 0) == 1000)
        #expect(ShortcutRules.target(ofID: ShortcutRules.id(ofAdded: 0), actions: 7, added: 2) == .added(0))
        #expect(ShortcutRules.target(ofID: ShortcutRules.id(ofAdded: 1), actions: 7, added: 2) == .added(1))
    }

    @Test func anIdOfNeitherIsNothing() {
        #expect(ShortcutRules.target(ofID: 7, actions: 7, added: 1) == nil)
        #expect(ShortcutRules.target(ofID: 999, actions: 7, added: 1) == nil)
        #expect(ShortcutRules.target(ofID: 1001, actions: 7, added: 1) == nil)
        #expect(ShortcutRules.target(ofID: 1000, actions: 7, added: 0) == nil)
        #expect(ShortcutRules.target(ofID: -1, actions: 7, added: 1) == nil)
    }
}
