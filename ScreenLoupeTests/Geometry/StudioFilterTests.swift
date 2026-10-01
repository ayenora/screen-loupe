import CoreGraphics
import Testing

private let ownPID: Int32 = 500

/// The windows of a desktop as the list shows it, front to back: the app's own first, then other
/// apps' and the system's, the wallpaper and the desktop icons among them.
private let viewer = ListedWindow(id: 1, ownerPID: ownPID)
private let captureArea = ListedWindow(id: 2, ownerPID: ownPID)
private let studioFrame = ListedWindow(id: 3, ownerPID: ownPID)
private let palette = ListedWindow(id: 4, ownerPID: ownPID)
private let backdrop = ListedWindow(id: 5, ownerPID: ownPID)
private let menuBar = ListedWindow(id: 10, ownerPID: 605)
private let safari = ListedWindow(id: 13, ownerPID: 700)
private let desktopIcons = ListedWindow(id: 16, ownerPID: 800)
private let wallpaper = ListedWindow(id: 18, ownerPID: 937)
private let serverWindow = ListedWindow(id: 19, ownerPID: nil)

private let desktop = [
    viewer, captureArea, studioFrame, palette, backdrop, menuBar, safari, desktopIcons, wallpaper, serverWindow,
]

/// What the studio keeps: the Viewer, the Capture Area frame and the backdrop.
private let kept: Set<CGWindowID> = [viewer.id, captureArea.id, backdrop.id]

struct StudioFilterTests {
    // MARK: Named one by one

    @Test func excludedIsTheAppsWindowsButTheKeptOnes() {
        #expect(StudioFilter.excluded(desktop, ownPID: ownPID, kept: kept) == [studioFrame.id, palette.id])
    }

    @Test func theBackdropIsKeptInThePicture() {
        #expect(!StudioFilter.excluded(desktop, ownPID: ownPID, kept: kept).contains(backdrop.id))
        // Not kept, it goes like any other window of the app.
        #expect(StudioFilter.excluded(desktop, ownPID: ownPID, kept: []).contains(backdrop.id))
    }

    @Test func nothingOfOtherAppsOrTheSystemIsLeftOut() {
        // The wallpaper and the desktop icons stay listed: the backdrop covers them on screen.
        let excluded = StudioFilter.excluded(desktop, ownPID: ownPID, kept: [])
        #expect(excluded == [viewer.id, captureArea.id, studioFrame.id, palette.id, backdrop.id])
    }

    @Test func aKeptNumberOfAnotherAppChangesNothing() {
        #expect(StudioFilter.excluded(desktop, ownPID: ownPID, kept: [wallpaper.id]).count == 5)
    }

    // MARK: The filter's path

    @Test func aListedAppIsExcludedAsAWhole() {
        #expect(StudioFilter.path(desktop, ownPID: ownPID, appIsListed: true, kept: kept) == .excludingApp)
    }

    @Test func anUnlistedAppNamesEveryWindow() {
        #expect(
            StudioFilter.path(desktop, ownPID: ownPID, appIsListed: false, kept: kept)
                == .excludingWindows([studioFrame.id, palette.id]))
    }

    @Test func anEmptyListStillExcludesTheApp() {
        #expect(StudioFilter.path([], ownPID: ownPID, appIsListed: true, kept: []) == .excludingApp)
        #expect(StudioFilter.path([], ownPID: ownPID, appIsListed: false, kept: []) == .excludingWindows([]))
    }

    // MARK: The Viewer's stream

    @Test func theViewersStreamKeepsOnlyTheBackdrop() {
        #expect(
            StudioFilter.path(desktop, ownPID: ownPID, appIsListed: false, kept: [backdrop.id])
                == .excludingWindows([viewer.id, captureArea.id, studioFrame.id, palette.id]))
    }

    @Test func theViewersStreamWithoutABackdropLeavesOutEveryWindowOfTheApp() {
        #expect(
            StudioFilter.path(desktop, ownPID: ownPID, appIsListed: false, kept: [])
                == .excludingWindows([viewer.id, captureArea.id, studioFrame.id, palette.id, backdrop.id]))
    }

    @Test func aKeptWindowNotListedChangesNothing() {
        // The backdrop's number, kept before the list is read again.
        #expect(
            StudioFilter.path([viewer, safari], ownPID: ownPID, appIsListed: false, kept: [backdrop.id])
                == .excludingWindows([viewer.id]))
    }

    // MARK: Hidden from a studio picture

    /// The studio's kept windows by number: the Viewer, the Capture Area frame and the backdrop.
    private let keptNumbers: Set<Int> = [1, 2, 5]

    @Test func aStudioPictureHidesEveryWindowButTheKeptOnes() {
        let hidden = (1...6).filter { StudioFilter.hides(number: $0, isShared: true, kept: keptNumbers) }
        #expect(hidden == [3, 4, 6])
    }

    @Test func aWindowScreenCaptureDoesNotSeeIsLeftAsItIs() {
        // Nothing to put back: it stays hidden from screen capture.
        #expect(!StudioFilter.hides(number: 3, isShared: false, kept: keptNumbers))
        #expect(!StudioFilter.hides(number: 1, isShared: false, kept: keptNumbers))
    }

    @Test func withNothingKeptEveryWindowIsHidden() {
        #expect([1, 2, 5].allSatisfy { StudioFilter.hides(number: $0, isShared: true, kept: []) })
    }

    @Test func aWindowNeverShownKeepsNothing() {
        // The Viewer not shown yet has no number: other windows without one are still hidden.
        #expect(StudioFilter.hides(number: -1, isShared: true, kept: [-1, 2]))
        #expect(StudioFilter.hides(number: 0, isShared: true, kept: [0]))
        #expect(!StudioFilter.hides(number: 2, isShared: true, kept: [-1, 2]))
    }

    /// A picture taken at once hides an open menu, the one of the command still fading out.
    @Test func aPictureAtOnceHidesAnOpenMenu() {
        #expect(StudioFilter.hides(number: 7, isShared: true, kept: [], isMenu: true, keepsMenus: false))
    }

    /// A picture taken by the timer keeps an open menu: the wait is for opening one to show.
    @Test func aTimedPictureKeepsAnOpenMenu() {
        #expect(!StudioFilter.hides(number: 7, isShared: true, kept: [], isMenu: true, keepsMenus: true))
        // Other windows of the app are hidden as ever.
        #expect(StudioFilter.hides(number: 8, isShared: true, kept: [], isMenu: false, keepsMenus: true))
        // A kept window stays, a menu or not.
        #expect(!StudioFilter.hides(number: 9, isShared: true, kept: [9], isMenu: false, keepsMenus: false))
        // A menu already hidden from capture isn't touched.
        #expect(!StudioFilter.hides(number: 7, isShared: false, kept: [], isMenu: true, keepsMenus: false))
    }
}
