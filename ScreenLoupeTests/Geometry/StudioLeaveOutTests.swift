import CoreGraphics
import Testing

private let ownPID: Int32 = 500

/// The windows of a desktop as the list shows it on macOS 27, front to back.
private let viewer = ListedWindow(id: 1, layer: 0, ownerPID: ownPID, ownerBundleID: "com.ayenora.screenloupe")
private let captureArea = ListedWindow(id: 2, layer: 25, ownerPID: ownPID, ownerBundleID: "com.ayenora.screenloupe")
private let studioFrame = ListedWindow(id: 3, layer: 25, ownerPID: ownPID, ownerBundleID: "com.ayenora.screenloupe")
private let palette = ListedWindow(id: 4, layer: 3, ownerPID: ownPID, ownerBundleID: "com.ayenora.screenloupe")
private let menuBar = ListedWindow(id: 10, layer: 24, ownerPID: 605, ownerBundleID: nil)
private let dockMenu = ListedWindow(id: 11, layer: 101, ownerPID: 900, ownerBundleID: StudioFilter.dockBundleID)
private let dock = ListedWindow(
    id: 12, layer: StudioFilter.dockLevel, ownerPID: 900, ownerBundleID: StudioFilter.dockBundleID)
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

private func leaveOut(
    dock: Bool = false, desktopIcons: Bool = false, background: StudioBackground = .screen,
    windows: Set<CGWindowID> = []
) -> StudioLeaveOut {
    StudioLeaveOut(dock: dock, desktopIcons: desktopIcons, background: background, windows: windows)
}

private func others(_ leaveOut: StudioLeaveOut, in windows: [ListedWindow] = desktop) -> [CGWindowID] {
    StudioFilter.othersLeftOut(windows, ownPID: ownPID, leaveOut)
}

struct StudioLeaveOutTests {
    // MARK: The levels

    @Test func theLevelsAreTheSystemsOnes() {
        // CGWindowLevel.h: kCGDesktopIconWindowLevel is kCGDesktopWindowLevel + 20, the Dock's 20.
        #expect(StudioFilter.desktopIconLevel == Int(CGWindowLevelForKey(.desktopWindow)) + 20)
        #expect(StudioFilter.dockLevel == 20)
    }

    // MARK: Settings

    @Test func theScreenBackgroundLeavesOutOnlyWhatIsChosen() {
        #expect(leaveOut() == StudioLeaveOut())
        let chosen = leaveOut(dock: true, desktopIcons: true, windows: [13])
        #expect(chosen.dock && chosen.desktopIcons && !chosen.wallpaper)
        #expect(chosen.windows == [13])
    }

    @Test func anyOtherBackgroundLeavesOutTheWallpaperAndTheDesktopIcons() {
        let backgrounds: [StudioBackground] = [
            .color(.white), .gradient(StudioBackground.gradients[0].gradient),
            .image(BackgroundImage(fileName: "a.png", name: "a.png")),
        ]
        for background in backgrounds {
            let settings = leaveOut(background: background)
            #expect(settings.wallpaper)
            #expect(settings.desktopIcons)
            #expect(!settings.dock)
        }
    }

    // MARK: Which windows

    @Test func nothingChosenLeavesOutNothing() {
        #expect(others(StudioLeaveOut()).isEmpty)
    }

    @Test func theDockIsTheDocksWindowAtTheDockLevelOnly() {
        #expect(others(leaveOut(dock: true)) == [dock.id])
        // Its menus, Finder, notifications and the menu bar stay.
        #expect(!others(leaveOut(dock: true)).contains(dockMenu.id))
    }

    @Test func anotherAppsWindowAtTheDockLevelIsNotTheDock() {
        let lookalike = ListedWindow(id: 40, layer: StudioFilter.dockLevel, ownerPID: 41, ownerBundleID: "com.example")
        #expect(others(leaveOut(dock: true), in: [lookalike]).isEmpty)
    }

    @Test func theDesktopIconsAreFindersWindowAtTheIconLevelOnly() {
        #expect(others(leaveOut(desktopIcons: true)) == [desktopIcons.id])
        #expect(!others(leaveOut(desktopIcons: true)).contains(finderWindow.id))
    }

    @Test func anotherAppsWindowAtTheIconLevelStays() {
        let widget = ListedWindow(
            id: 40, layer: StudioFilter.desktopIconLevel, ownerPID: 41, ownerBundleID: "com.apple.widgets")
        #expect(others(leaveOut(desktopIcons: true), in: [widget]).isEmpty)
        #expect(others(leaveOut(background: .color(.black)), in: [widget]).isEmpty)
    }

    @Test func theWallpaperIsEverythingBelowTheIconsWhoeverDrawsIt() {
        let left = others(leaveOut(background: .color(.white)))
        // With the wallpaper go the desktop icons.
        #expect(left == [desktopIcons.id, stageManagerWallpaper.id, wallpaper.id, serverBackdrop.id])
    }

    @Test func aWallpaperOfTheDockAtTheDesktopLevelGoesToo() {
        // Earlier macOS versions may draw it in the Dock.
        let old = ListedWindow(
            id: 40, layer: Int(CGWindowLevelForKey(.desktopWindow)), ownerPID: 900,
            ownerBundleID: StudioFilter.dockBundleID)
        #expect(others(leaveOut(background: .color(.white)), in: [old]) == [old.id])
        #expect(others(leaveOut(dock: true), in: [old]).isEmpty)
    }

    @Test func aWindowJustAboveTheIconLevelIsNotWallpaper() {
        let above = ListedWindow(id: 40, layer: StudioFilter.desktopIconLevel + 1, ownerPID: nil, ownerBundleID: nil)
        #expect(others(leaveOut(background: .color(.white)), in: [above]).isEmpty)
    }

    @Test func theOwnerlessBandAboveTheIconsStaysWhateverIsLeftOut() {
        let all = leaveOut(dock: true, desktopIcons: true, background: .color(.white))
        #expect(!others(all).contains(topBand.id))
        #expect(!StudioFilter.excluded(desktop, ownPID: ownPID, kept: [], all).contains(topBand.id))
    }

    @Test func anotherAppsDesktopLevelWindowGoesWithTheWallpaper() {
        // A desktop widget drawn at the desktop's level, as Übersicht does.
        let widget = ListedWindow(
            id: 40, layer: Int(CGWindowLevelForKey(.desktopWindow)), ownerPID: 41, ownerBundleID: "tracesOf.Uebersicht")
        #expect(others(leaveOut(background: .color(.white)), in: [widget]) == [widget.id])
        #expect(others(leaveOut(desktopIcons: true), in: [widget]).isEmpty)
    }

    @Test func pointedWindowsAreLeftOutByNumber() {
        #expect(others(leaveOut(windows: [safari.id, finderWindow.id])) == [safari.id, finderWindow.id])
    }

    @Test func aPointedWindowThatIsNotListedIsIgnored() {
        #expect(others(leaveOut(windows: [999])).isEmpty)
    }

    @Test func everythingTogetherKeepsListOrderWithoutRepeats() {
        let all = leaveOut(dock: true, desktopIcons: true, background: .color(.white), windows: [safari.id, dock.id])
        #expect(
            others(all) == [
                dock.id, safari.id, desktopIcons.id, stageManagerWallpaper.id, wallpaper.id, serverBackdrop.id,
            ])
    }

    @Test func theAppsOwnWindowsAreNeverAmongTheOthers() {
        // Even named by number, or at a level that would count as wallpaper.
        let ownLow = ListedWindow(
            id: 41, layer: StudioFilter.desktopIconLevel - 1, ownerPID: ownPID, ownerBundleID: nil)
        let all = leaveOut(dock: true, background: .color(.white), windows: [viewer.id, palette.id])
        #expect(others(all, in: desktop + [ownLow]).allSatisfy { ![1, 2, 3, 4, 41].contains($0) })
    }

    // MARK: Named one by one

    @Test func excludedIsTheAppsWindowsButTheKeptOnesThenTheOthers() {
        let kept: Set<CGWindowID> = [viewer.id, captureArea.id]
        #expect(StudioFilter.excluded(desktop, ownPID: ownPID, kept: kept, StudioLeaveOut()) == [3, 4])
        #expect(
            StudioFilter.excluded(desktop, ownPID: ownPID, kept: kept, leaveOut(dock: true, windows: [safari.id]))
                == [3, 4, dock.id, safari.id])
    }

    @Test func keptWindowsOfTheAppStayWhateverIsLeftOut() {
        let kept: Set<CGWindowID> = [viewer.id, captureArea.id]
        let all = leaveOut(dock: true, desktopIcons: true, background: .color(.white), windows: [viewer.id])
        let excluded = StudioFilter.excluded(desktop, ownPID: ownPID, kept: kept, all)
        #expect(!excluded.contains(viewer.id))
        #expect(!excluded.contains(captureArea.id))
    }

    @Test func aKeptNumberOfAnotherAppDoesNotKeepIt() {
        // `kept` names the app's windows; another app's window left out stays left out.
        let excluded = StudioFilter.excluded(
            desktop, ownPID: ownPID, kept: [safari.id], leaveOut(windows: [safari.id]))
        #expect(excluded.contains(safari.id))
    }

    // MARK: The filter's path

    @Test func nothingOfOtherAppsExcludesTheAppAsAWhole() {
        #expect(
            StudioFilter.path(desktop, ownPID: ownPID, appIsListed: true, kept: [1, 2], StudioLeaveOut())
                == .excludingApp)
        // Choices that find nothing on screen leave nothing out either: the Dock hidden.
        let noDock = desktop.filter { $0 != dock }
        #expect(
            StudioFilter.path(noDock, ownPID: ownPID, appIsListed: true, kept: [1, 2], leaveOut(dock: true))
                == .excludingApp)
        // A pointed window that closed.
        #expect(
            StudioFilter.path(desktop, ownPID: ownPID, appIsListed: true, kept: [1, 2], leaveOut(windows: [999]))
                == .excludingApp)
    }

    @Test func anythingOfOtherAppsNamesEveryWindow() {
        let path = StudioFilter.path(
            desktop, ownPID: ownPID, appIsListed: true, kept: [1, 2], leaveOut(windows: [safari.id]))
        #expect(path == .excludingWindows([3, 4, safari.id]))
    }

    @Test func anUnlistedAppNamesEveryWindowAlsoWithNothingElse() {
        #expect(
            StudioFilter.path(desktop, ownPID: ownPID, appIsListed: false, kept: [1, 2], StudioLeaveOut())
                == .excludingWindows([3, 4]))
        #expect(
            StudioFilter.path(desktop, ownPID: ownPID, appIsListed: false, kept: [1, 2], leaveOut(dock: true))
                == .excludingWindows([3, 4, dock.id]))
    }

    @Test func anEmptyListStillExcludesTheApp() {
        #expect(StudioFilter.path([], ownPID: ownPID, appIsListed: true, kept: [], StudioLeaveOut()) == .excludingApp)
        #expect(
            StudioFilter.path([], ownPID: ownPID, appIsListed: false, kept: [], leaveOut(dock: true))
                == .excludingWindows([]))
    }

    // MARK: The left-out set

    @Test func aClickLeavesOutAndASecondBringsBack() {
        let one = LeftOutWindows.toggled(7, in: [])
        #expect(one == [7])
        let two = LeftOutWindows.toggled(9, in: one)
        #expect(two == [7, 9])
        #expect(LeftOutWindows.toggled(7, in: two) == [9])
        #expect(LeftOutWindows.toggled(9, in: [9]).isEmpty)
    }

    @Test func windowsThatClosedAreDropped() {
        #expect(LeftOutWindows.keeping([1, 2, 3], existing: [2, 3, 4]) == [2, 3])
        #expect(LeftOutWindows.keeping([1], existing: []).isEmpty)
        #expect(LeftOutWindows.keeping([], existing: [1, 2]).isEmpty)
    }

    // MARK: Dimmed rects

    private func window(_ id: CGWindowID, _ frame: CGRect, onScreen: Bool = true) -> ScreenWindow {
        ScreenWindow(id: id, frame: frame, layer: 0, isOnScreen: onScreen, alpha: 1)
    }

    private let frame = CGRect(x: 100, y: 100, width: 800, height: 500)

    @Test func aWindowInsideTheFrameIsDimmedWhole() {
        let inside = window(1, CGRect(x: 200, y: 200, width: 300, height: 200))
        #expect(LeftOutWindows.dimmedRects([1], stack: [inside], frame: frame, scale: 2) == [inside.frame])
    }

    @Test func aWindowPartlyOutsideIsClippedToTheFrame() {
        let partly = window(1, CGRect(x: 50, y: 400, width: 300, height: 400))
        #expect(
            LeftOutWindows.dimmedRects([1], stack: [partly], frame: frame, scale: 1)
                == [CGRect(x: 100, y: 400, width: 250, height: 200)])
    }

    @Test func aWindowCoveringTheFrameDimsAllOfIt() {
        let big = window(1, CGRect(x: 0, y: 0, width: 2000, height: 2000))
        #expect(LeftOutWindows.dimmedRects([1], stack: [big], frame: frame, scale: 2) == [frame])
    }

    @Test func aWindowWhollyOutsideOrTouchingTheEdgeDimsNothing() {
        let outside = window(1, CGRect(x: 1000, y: 100, width: 200, height: 200))
        let touching = window(2, CGRect(x: 900, y: 100, width: 200, height: 200))
        #expect(LeftOutWindows.dimmedRects([1, 2], stack: [outside, touching], frame: frame, scale: 2).isEmpty)
    }

    @Test func onlyLeftOutOnScreenWindowsAreDimmed() {
        let kept = window(1, CGRect(x: 200, y: 200, width: 100, height: 100))
        let hidden = window(2, CGRect(x: 300, y: 300, width: 100, height: 100), onScreen: false)
        let left = window(3, CGRect(x: 400, y: 300, width: 100, height: 100))
        #expect(
            LeftOutWindows.dimmedRects([2, 3], stack: [kept, hidden, left], frame: frame, scale: 2) == [left.frame])
    }

    @Test func overlappingWindowsGiveARectEachInListOrder() {
        let front = window(1, CGRect(x: 200, y: 200, width: 300, height: 200))
        let back = window(2, CGRect(x: 300, y: 300, width: 300, height: 200))
        #expect(
            LeftOutWindows.dimmedRects([1, 2], stack: [front, back], frame: frame, scale: 2) == [
                front.frame, back.frame,
            ])
    }

    @Test func aFractionalWindowEdgeWidensToWholePixelsOnOneX() {
        // On a 1× display 150.5 widens to 150 and 350.25 to 351.
        let odd = window(1, CGRect(x: 150.5, y: 200.25, width: 199.75, height: 100.5))
        #expect(
            LeftOutWindows.dimmedRects([1], stack: [odd], frame: frame, scale: 1)
                == [CGRect(x: 150, y: 200, width: 201, height: 101)])
    }

    @Test func aHalfPointEdgeStaysOnTwoX() {
        // On a 2× display half points are whole pixels: 150.5 stays, 150.25 widens to 150.
        let half = window(1, CGRect(x: 150.5, y: 200.25, width: 100, height: 100))
        let rect = LeftOutWindows.dimmedRects([1], stack: [half], frame: frame, scale: 2)[0]
        #expect(rect.minX == CGFloat(150.5))
        #expect(rect.minY == CGFloat(200))
        #expect(rect.maxX == CGFloat(250.5))
        #expect(rect.maxY == CGFloat(300.5))
    }

    @Test func wideningNeverReachesPastTheFrame() {
        let odd = window(1, CGRect(x: 850.5, y: 550.5, width: 400, height: 400))
        let rects = LeftOutWindows.dimmedRects([1], stack: [odd], frame: frame, scale: 1)
        #expect(rects == [CGRect(x: 850, y: 550, width: 50, height: 50)])
        #expect(frame.contains(rects[0]))
    }

    @Test func aFrameOnADisplayLeftOfAndBelowThePrimary() {
        // Negative global coordinates, 2×.
        let left = CGRect(x: -1500, y: -700, width: 1000, height: 600)
        let partly = window(1, CGRect(x: -1600, y: -200, width: 400, height: 300))
        #expect(
            LeftOutWindows.dimmedRects([1], stack: [partly], frame: left, scale: 2)
                == [CGRect(x: -1500, y: -200, width: 300, height: 100)])
        // Fractional negative edges widen outward too: -1250.3 to -1250.5 on 2×.
        let odd = window(2, CGRect(x: -1250.3, y: -600.3, width: 100, height: 100))
        let rect = LeftOutWindows.dimmedRects([2], stack: [odd], frame: left, scale: 2)[0]
        #expect(rect.minX == CGFloat(-1250.5))
        #expect(rect.minY == CGFloat(-600.5))
        #expect(rect.maxX == CGFloat(-1150.0))
        #expect(rect.maxY == CGFloat(-500.0))
    }

    @Test func noLeftOutWindowsDimNothing() {
        let inside = window(1, CGRect(x: 200, y: 200, width: 300, height: 200))
        #expect(LeftOutWindows.dimmedRects([], stack: [inside], frame: frame, scale: 2).isEmpty)
    }

    // MARK: Windows in front

    @Test func aKeptWindowInFrontCutsTheDim() {
        // The left-out window at x 200...600, y 200...500; a kept one in front over its right half.
        let left = window(1, CGRect(x: 200, y: 200, width: 400, height: 300))
        let kept = window(2, CGRect(x: 400, y: 100, width: 600, height: 600))
        #expect(
            LeftOutWindows.dimmedRects([1], stack: [kept, left], frame: frame, scale: 2)
                == [CGRect(x: 200, y: 200, width: 200, height: 300)])
    }

    @Test func aKeptWindowBehindCutsNothing() {
        let left = window(1, CGRect(x: 200, y: 200, width: 400, height: 300))
        let behind = window(2, CGRect(x: 400, y: 100, width: 600, height: 600))
        #expect(LeftOutWindows.dimmedRects([1], stack: [left, behind], frame: frame, scale: 2) == [left.frame])
    }

    @Test func aWindowInFrontInsideItLeavesARing() {
        let left = window(1, CGRect(x: 200, y: 200, width: 400, height: 300))
        let nested = window(2, CGRect(x: 300, y: 250, width: 100, height: 100))
        let rects = LeftOutWindows.dimmedRects([1], stack: [nested, left], frame: frame, scale: 1)
        #expect(
            rects == [
                CGRect(x: 200, y: 350, width: 400, height: 150), CGRect(x: 200, y: 200, width: 400, height: 50),
                CGRect(x: 200, y: 250, width: 100, height: 100), CGRect(x: 400, y: 250, width: 200, height: 100),
            ])
        // Together they are the window less the nested one.
        #expect(rects.reduce(0) { $0 + $1.width * $1.height } == CGFloat(400 * 300 - 100 * 100))
        #expect(rects.allSatisfy { !$0.intersects(nested.frame) })
    }

    @Test func aWhollyCoveredWindowIsNotDimmed() {
        let left = window(1, CGRect(x: 200, y: 200, width: 400, height: 300))
        let cover = window(2, CGRect(x: 150, y: 150, width: 500, height: 400))
        #expect(LeftOutWindows.dimmedRects([1], stack: [cover, left], frame: frame, scale: 2).isEmpty)
    }

    @Test func aLeftOutWindowInFrontHidesNothing() {
        // Both go from the picture, so the one behind is dimmed where the front one covers it too.
        let front = window(1, CGRect(x: 200, y: 200, width: 300, height: 200))
        let back = window(2, CGRect(x: 300, y: 300, width: 300, height: 200))
        #expect(
            LeftOutWindows.dimmedRects([1, 2], stack: [front, back], frame: frame, scale: 2) == [
                front.frame, back.frame,
            ])
    }

    @Test func severalWindowsInFrontCutInTurn() {
        let left = window(1, CGRect(x: 100, y: 100, width: 800, height: 500))
        let a = window(2, CGRect(x: 100, y: 100, width: 400, height: 500))
        let b = window(3, CGRect(x: 500, y: 350, width: 400, height: 250))
        #expect(
            LeftOutWindows.dimmedRects([1], stack: [a, b, left], frame: frame, scale: 2)
                == [CGRect(x: 500, y: 100, width: 400, height: 250)])
    }

    @Test func anOffScreenWindowInFrontCutsNothing() {
        let left = window(1, CGRect(x: 200, y: 200, width: 400, height: 300))
        let hidden = window(2, CGRect(x: 150, y: 150, width: 500, height: 400), onScreen: false)
        #expect(LeftOutWindows.dimmedRects([1], stack: [hidden, left], frame: frame, scale: 2) == [left.frame])
    }

    @Test func aCutOnAFractionalEdgeWidensOutwardOnOneX() {
        // In front from x 400.5: on 1× the dim widens to 401.
        let left = window(1, CGRect(x: 200, y: 200, width: 400, height: 300))
        let kept = window(2, CGRect(x: 400.5, y: 100, width: 600, height: 600))
        #expect(
            LeftOutWindows.dimmedRects([1], stack: [kept, left], frame: frame, scale: 1)
                == [CGRect(x: 200, y: 200, width: 201, height: 300)])
        // On 2× 400.5 is a pixel edge and stays.
        #expect(
            LeftOutWindows.dimmedRects([1], stack: [kept, left], frame: frame, scale: 2)
                == [CGRect(x: 200, y: 200, width: 200.5, height: 300)])
    }

    @Test func windowsInFrontOnADisplayLeftOfAndBelowThePrimary() {
        let left = CGRect(x: -1500, y: -700, width: 1000, height: 600)
        let leftOut = window(1, CGRect(x: -1400, y: -600, width: 600, height: 400))
        let kept = window(2, CGRect(x: -1100, y: -650, width: 700, height: 200))
        // Less the kept window's part, y -600...-450 and x -1100...-800: an L of two pieces.
        #expect(
            LeftOutWindows.dimmedRects([1], stack: [kept, leftOut], frame: left, scale: 2) == [
                CGRect(x: -1400, y: -450, width: 600, height: 250), CGRect(x: -1400, y: -600, width: 300, height: 150),
            ])
    }

    // MARK: Subtracting

    @Test func subtractingWithoutOverlapKeepsTheRect() {
        let rect = CGRect(x: 0, y: 0, width: 10, height: 10)
        #expect(LeftOutWindows.subtracting(CGRect(x: 20, y: 0, width: 5, height: 5), from: rect) == [rect])
        // Touching edges don't overlap.
        #expect(LeftOutWindows.subtracting(CGRect(x: 10, y: 0, width: 5, height: 10), from: rect) == [rect])
    }

    @Test func subtractingAllOfItLeavesNothing() {
        let rect = CGRect(x: 0, y: 0, width: 10, height: 10)
        #expect(LeftOutWindows.subtracting(rect, from: rect).isEmpty)
        #expect(LeftOutWindows.subtracting(rect.insetBy(dx: -5, dy: -5), from: rect).isEmpty)
    }

    @Test func subtractingACornerLeavesTwoPieces() {
        let rect = CGRect(x: 0, y: 0, width: 10, height: 10)
        #expect(
            LeftOutWindows.subtracting(CGRect(x: 5, y: 5, width: 10, height: 10), from: rect) == [
                CGRect(x: 0, y: 0, width: 10, height: 5), CGRect(x: 0, y: 5, width: 5, height: 5),
            ])
    }

    @Test func subtractingAStripAcrossLeavesTwoPieces() {
        let rect = CGRect(x: 0, y: 0, width: 10, height: 10)
        #expect(
            LeftOutWindows.subtracting(CGRect(x: 3, y: -5, width: 4, height: 20), from: rect) == [
                CGRect(x: 0, y: 0, width: 3, height: 10), CGRect(x: 7, y: 0, width: 3, height: 10),
            ])
    }

    // MARK: The stack

    @Test func theStackTakesOtherAppsOrdinaryAndFloatingWindows() {
        #expect(LeftOutWindows.isInStack(layer: 0, alpha: 1, isEmpty: false, isOwn: false, ownInStack: false))
        #expect(LeftOutWindows.isInStack(layer: 3, alpha: 1, isEmpty: false, isOwn: false, ownInStack: false))
        #expect(
            LeftOutWindows.isInStack(
                layer: StudioFilter.dockLevel - 1, alpha: 1, isEmpty: false, isOwn: false, ownInStack: false))
    }

    @Test func theStackLeavesOutTheDockMenuBarDesktopAndInvisibleWindows() {
        for layer in [StudioFilter.dockLevel, 24, 25, 101, StudioFilter.desktopIconLevel, -1] {
            #expect(!LeftOutWindows.isInStack(layer: layer, alpha: 1, isEmpty: false, isOwn: false, ownInStack: false))
        }
        #expect(!LeftOutWindows.isInStack(layer: 0, alpha: 0, isEmpty: false, isOwn: false, ownInStack: false))
        #expect(!LeftOutWindows.isInStack(layer: 0, alpha: 1, isEmpty: true, isOwn: false, ownInStack: false))
    }

    @Test func theStackTakesOnlyTheNamedWindowsOfTheApp() {
        // The Viewer or the palette, at any level; not the frames or the dim overlay.
        #expect(LeftOutWindows.isInStack(layer: 0, alpha: 1, isEmpty: false, isOwn: true, ownInStack: true))
        #expect(LeftOutWindows.isInStack(layer: 27, alpha: 1, isEmpty: false, isOwn: true, ownInStack: true))
        #expect(!LeftOutWindows.isInStack(layer: 25, alpha: 1, isEmpty: false, isOwn: true, ownInStack: false))
        #expect(!LeftOutWindows.isInStack(layer: 0, alpha: 1, isEmpty: false, isOwn: true, ownInStack: false))
        #expect(!LeftOutWindows.isInStack(layer: 0, alpha: 0, isEmpty: false, isOwn: true, ownInStack: true))
    }
}
