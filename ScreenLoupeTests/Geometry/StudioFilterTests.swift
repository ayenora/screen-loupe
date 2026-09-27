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
}
