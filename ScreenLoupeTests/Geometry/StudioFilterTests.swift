import CoreGraphics
import Testing

private let ownPID: Int32 = 500
private let dockLevel = Int(CGWindowLevelForKey(.dockWindow))

/// The windows of a desktop as the list shows it on macOS 27, front to back.
private let viewer = ListedWindow(id: 1, layer: 0, ownerPID: ownPID, ownerBundleID: "com.ayenora.screenloupe")
private let captureArea = ListedWindow(id: 2, layer: 25, ownerPID: ownPID, ownerBundleID: "com.ayenora.screenloupe")
private let studioFrame = ListedWindow(id: 3, layer: 25, ownerPID: ownPID, ownerBundleID: "com.ayenora.screenloupe")
private let palette = ListedWindow(id: 4, layer: 3, ownerPID: ownPID, ownerBundleID: "com.ayenora.screenloupe")
private let menuBar = ListedWindow(id: 10, layer: 24, ownerPID: 605, ownerBundleID: nil)
private let dockMenu = ListedWindow(id: 11, layer: 101, ownerPID: 900, ownerBundleID: "com.apple.dock")
private let dock = ListedWindow(id: 12, layer: dockLevel, ownerPID: 900, ownerBundleID: "com.apple.dock")
private let safari = ListedWindow(id: 13, layer: 0, ownerPID: 700, ownerBundleID: "com.apple.Safari")
private let finderWindow = ListedWindow(id: 14, layer: 0, ownerPID: 800, ownerBundleID: StudioFilter.finderBundleID)
private let notification = ListedWindow(
    id: 15, layer: 23, ownerPID: 950, ownerBundleID: "com.apple.notificationcenterui")
private let desktopIcons = ListedWindow(
    id: 16, layer: StudioFilter.desktopIconLevel, ownerPID: 800, ownerBundleID: StudioFilter.finderBundleID)
private let stageManagerWallpaper = ListedWindow(
    id: 17, layer: Int(CGWindowLevelForKey(.desktopWindow)) - 1, ownerPID: 926, ownerBundleID: "com.apple.WindowManager"
)
private let wallpaper = ListedWindow(
    id: 18, layer: Int(CGWindowLevelForKey(.desktopWindow)) - 2, ownerPID: 937,
    ownerBundleID: "com.apple.wallpaper.agent")
private let serverBackdrop = ListedWindow(
    id: 19, layer: Int(CGWindowLevelForKey(.desktopWindow)) - 3, ownerPID: nil, ownerBundleID: nil)

/// Observed on macOS 27: a window server window without an owner one level above the desktop
/// icons, 91 pt tall along the top of the display. What it draws is unknown; it stays in pictures.
private let topBand = ListedWindow(id: 20, layer: StudioFilter.desktopIconLevel + 1, ownerPID: nil, ownerBundleID: nil)

private let desktop = [
    viewer, captureArea, studioFrame, palette, menuBar, dockMenu, dock, safari, finderWindow, notification, topBand,
    desktopIcons, stageManagerWallpaper, wallpaper, serverBackdrop,
]

private func others(_ leavingOutDesktop: Bool = true, in windows: [ListedWindow] = desktop) -> [CGWindowID] {
    StudioFilter.othersLeftOut(windows, ownPID: ownPID, leavingOutDesktop: leavingOutDesktop)
}

struct StudioFilterTests {
    // MARK: The levels

    @Test func theIconLevelIsTheSystemsOne() {
        // CGWindowLevel.h: kCGDesktopIconWindowLevel is kCGDesktopWindowLevel + 20.
        #expect(StudioFilter.desktopIconLevel == Int(CGWindowLevelForKey(.desktopWindow)) + 20)
    }

    // MARK: Which windows

    @Test func theScreenBackgroundLeavesOutNothing() {
        #expect(others(false).isEmpty)
        #expect(others(StudioBackground.screen.leavesOutWallpaper).isEmpty)
    }

    @Test func theWallpaperIsEverythingBelowTheIconsWhoeverDrawsIt() {
        // With the wallpaper go the desktop icons; the Dock, its menus, Finder's windows,
        // notifications and the menu bar stay.
        #expect(others() == [desktopIcons.id, stageManagerWallpaper.id, wallpaper.id, serverBackdrop.id])
    }

    @Test func theDesktopIconsAreFindersWindowAtTheIconLevelOnly() {
        #expect(others().contains(desktopIcons.id))
        #expect(!others().contains(finderWindow.id))
    }

    @Test func anotherAppsWindowAtTheIconLevelStays() {
        let widget = ListedWindow(
            id: 40, layer: StudioFilter.desktopIconLevel, ownerPID: 41, ownerBundleID: "com.apple.widgets")
        #expect(others(in: [widget]).isEmpty)
    }

    @Test func aWallpaperOfTheDockAtTheDesktopLevelGoesToo() {
        // Earlier macOS versions may draw it in the Dock.
        let old = ListedWindow(
            id: 40, layer: Int(CGWindowLevelForKey(.desktopWindow)), ownerPID: 900, ownerBundleID: "com.apple.dock")
        #expect(others(in: [old]) == [old.id])
        #expect(others(false, in: [old]).isEmpty)
    }

    @Test func aWindowJustAboveTheIconLevelIsNotWallpaper() {
        let above = ListedWindow(id: 40, layer: StudioFilter.desktopIconLevel + 1, ownerPID: nil, ownerBundleID: nil)
        #expect(others(in: [above]).isEmpty)
    }

    @Test func theOwnerlessBandAboveTheIconsStays() {
        #expect(!others().contains(topBand.id))
        #expect(!StudioFilter.excluded(desktop, ownPID: ownPID, kept: [], leavingOutDesktop: true).contains(topBand.id))
    }

    @Test func anotherAppsDesktopLevelWindowGoesWithTheWallpaper() {
        // A desktop widget drawn at the desktop's level, as Übersicht does.
        let widget = ListedWindow(
            id: 40, layer: Int(CGWindowLevelForKey(.desktopWindow)), ownerPID: 41, ownerBundleID: "tracesOf.Uebersicht")
        #expect(others(in: [widget]) == [widget.id])
        #expect(others(false, in: [widget]).isEmpty)
    }

    @Test func theAppsOwnWindowsAreNeverAmongTheOthers() {
        // Even at a level that would count as wallpaper.
        let ownLow = ListedWindow(
            id: 41, layer: StudioFilter.desktopIconLevel - 1, ownerPID: ownPID, ownerBundleID: nil)
        #expect(others(in: desktop + [ownLow]).allSatisfy { ![1, 2, 3, 4, 41].contains($0) })
    }

    // MARK: Named one by one

    @Test func excludedIsTheAppsWindowsButTheKeptOnesThenTheOthers() {
        let kept: Set<CGWindowID> = [viewer.id, captureArea.id]
        #expect(StudioFilter.excluded(desktop, ownPID: ownPID, kept: kept, leavingOutDesktop: false) == [3, 4])
        #expect(
            StudioFilter.excluded(desktop, ownPID: ownPID, kept: kept, leavingOutDesktop: true)
                == [3, 4, desktopIcons.id, stageManagerWallpaper.id, wallpaper.id, serverBackdrop.id])
    }

    @Test func keptWindowsOfTheAppStayWithTheDesktopLeftOut() {
        let kept: Set<CGWindowID> = [viewer.id, captureArea.id]
        let excluded = StudioFilter.excluded(desktop, ownPID: ownPID, kept: kept, leavingOutDesktop: true)
        #expect(!excluded.contains(viewer.id))
        #expect(!excluded.contains(captureArea.id))
    }

    @Test func aKeptNumberOfAnotherAppDoesNotKeepItsWallpaper() {
        // `kept` names the app's windows; the wallpaper named there is still left out.
        let excluded = StudioFilter.excluded(desktop, ownPID: ownPID, kept: [wallpaper.id], leavingOutDesktop: true)
        #expect(excluded.contains(wallpaper.id))
    }

    // MARK: The filter's path

    @Test func theScreenBackgroundExcludesTheAppAsAWhole() {
        #expect(
            StudioFilter.path(desktop, ownPID: ownPID, appIsListed: true, kept: [1, 2], leavingOutDesktop: false)
                == .excludingApp)
    }

    @Test func aDesktopNotListedLeavesNothingOutEither() {
        let noDesktop = desktop.filter {
            ![desktopIcons, stageManagerWallpaper, wallpaper, serverBackdrop].contains($0)
        }
        #expect(
            StudioFilter.path(noDesktop, ownPID: ownPID, appIsListed: true, kept: [1, 2], leavingOutDesktop: true)
                == .excludingApp)
    }

    @Test func leavingOutTheDesktopNamesEveryWindow() {
        let path = StudioFilter.path(desktop, ownPID: ownPID, appIsListed: true, kept: [1, 2], leavingOutDesktop: true)
        #expect(
            path
                == .excludingWindows([3, 4, desktopIcons.id, stageManagerWallpaper.id, wallpaper.id, serverBackdrop.id])
        )
    }

    @Test func anUnlistedAppNamesEveryWindowAlsoWithNothingElse() {
        #expect(
            StudioFilter.path(desktop, ownPID: ownPID, appIsListed: false, kept: [1, 2], leavingOutDesktop: false)
                == .excludingWindows([3, 4]))
    }

    @Test func anEmptyListStillExcludesTheApp() {
        #expect(
            StudioFilter.path([], ownPID: ownPID, appIsListed: true, kept: [], leavingOutDesktop: true) == .excludingApp
        )
        #expect(
            StudioFilter.path([], ownPID: ownPID, appIsListed: false, kept: [], leavingOutDesktop: true)
                == .excludingWindows([]))
    }
}
