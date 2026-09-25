import CoreGraphics
import Testing

/// 800%, the image's top-left at (16, 8) in the viewport, a 40×30 px Capture Area.
private let state = ZoomPanState(
    zoom: 8, offset: CGPoint(x: 16, y: 8), contentSize: CGSize(width: 40, height: 30),
    viewportSize: CGSize(width: 400, height: 300))
private let content = CGSize(width: 40, height: 30)

struct PixelSelectionTests {
    @Test func aDragCoversEveryPixelItTouchesWhicheverWayItGoes() {
        // Viewport x 20 is source 0.5, x 43 is 3.375: pixels 0 through 3.
        let forward = PixelSelection.rect(from: CGPoint(x: 20, y: 12), to: CGPoint(x: 43, y: 30), in: state)
        let backward = PixelSelection.rect(from: CGPoint(x: 43, y: 30), to: CGPoint(x: 20, y: 12), in: state)
        #expect(forward == CGRect(x: 0, y: 0, width: 4, height: 3))
        #expect(backward == forward)
    }

    @Test func aClickSelectsOnePixel() {
        #expect(
            PixelSelection.rect(from: CGPoint(x: 60, y: 60), to: CGPoint(x: 61, y: 61), in: state)
                == CGRect(x: 5, y: 6, width: 1, height: 1))
    }

    @Test func aDragBeyondTheImageStopsAtItsEdges() {
        let rect = PixelSelection.rect(from: CGPoint(x: 300, y: 200), to: CGPoint(x: 999, y: 999), in: state)
        #expect(rect == CGRect(x: 35, y: 24, width: 5, height: 6))
        #expect(PixelSelection.rect(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 10, y: 5), in: state) == nil)
    }

    @Test func handlesMoveTheirEdgesToTheNearestPixelBoundary() {
        let rect = CGRect(x: 10, y: 10, width: 5, height: 5)
        #expect(
            PixelSelection.resized(rect, handle: .right, to: CGPoint(x: 17.4, y: 0), contentSize: content)
                == CGRect(x: 10, y: 10, width: 7, height: 5))
        #expect(
            PixelSelection.resized(rect, handle: .topLeft, to: CGPoint(x: 8.6, y: 7.2), contentSize: content)
                == CGRect(x: 9, y: 7, width: 6, height: 8))
    }

    @Test func aSelectionKeepsAtLeastOnePixelAndStaysInTheImage() {
        let rect = CGRect(x: 10, y: 10, width: 5, height: 5)
        #expect(
            PixelSelection.resized(rect, handle: .left, to: CGPoint(x: 30, y: 0), contentSize: content)
                == CGRect(x: 14, y: 10, width: 1, height: 5))
        #expect(
            PixelSelection.resized(rect, handle: .bottom, to: CGPoint(x: 0, y: 99), contentSize: content)
                == CGRect(x: 10, y: 10, width: 5, height: 20))
    }

    @Test func movingKeepsTheSizeInWholePixelsInsideTheImage() {
        let rect = CGRect(x: 10, y: 10, width: 5, height: 5)
        #expect(
            PixelSelection.moved(rect, by: CGPoint(x: 2.6, y: -1.2), contentSize: content)
                == CGRect(x: 13, y: 9, width: 5, height: 5))
        #expect(
            PixelSelection.moved(rect, by: CGPoint(x: 99, y: -99), contentSize: content)
                == CGRect(x: 35, y: 0, width: 5, height: 5))
    }

    @Test func aSelectionPastAShrunkAreaIsCutToIt() {
        let rect = CGRect(x: 30, y: 20, width: 20, height: 20)
        #expect(PixelSelection.clamped(rect, to: content) == CGRect(x: 30, y: 20, width: 10, height: 10))
        #expect(PixelSelection.clamped(rect, to: CGSize(width: 20, height: 20)) == nil)
    }

    @Test func handlesSitOnTheSelectionsEdgesInTheViewport() {
        let rect = CGRect(x: 1, y: 2, width: 4, height: 2)
        #expect(PixelSelection.handlePoint(.topLeft, of: rect, in: state) == CGPoint(x: 24, y: 24))
        #expect(PixelSelection.handlePoint(.bottom, of: rect, in: state) == CGPoint(x: 40, y: 40))
    }

    @Test func theLabelGivesSizeAndPlace() {
        #expect(PixelSelection.label(CGRect(x: 11, y: 11, width: 12, height: 5)) == "12 × 5 px · x 11, y 11")
    }

    @Test func draggingTheAreasLeftAndTopEdgesKeepsTheSelectionOnItsPixels() {
        // The left edge dragged 3 px right and the top edge 2 px down: the area shrinks to 37 × 28.
        let rect = CGRect(x: 10, y: 10, width: 5, height: 5)
        let shift = CGPoint(x: 3, y: 2)
        let resized = state.resizingContent(to: CGSize(width: 37, height: 28), originShift: shift)
        let followed = PixelSelection.followingAreaOrigin(rect, shift: shift)
        #expect(followed == CGRect(x: 7, y: 8, width: 5, height: 5))
        #expect(
            resized.imageRect(origin: followed.origin, size: followed.size)
                == state.imageRect(origin: rect.origin, size: rect.size))
    }
}

struct ViewRegionTests {
    let viewport = CGSize(width: 400, height: 300)

    @Test func aRegionIsWholeViewportPixelsEitherWay() {
        let rect = ViewRegion.rect(from: CGPoint(x: 120.6, y: 80.2), to: CGPoint(x: 20.4, y: 10.5), viewport: viewport)
        #expect(rect == CGRect(x: 20, y: 11, width: 101, height: 69))
    }

    @Test func aRegionStopsAtTheViewportAndNeedsAPixel() {
        #expect(
            ViewRegion.rect(from: CGPoint(x: -50, y: 250), to: CGPoint(x: 30, y: 400), viewport: viewport)
                == CGRect(x: 0, y: 250, width: 30, height: 50))
        #expect(ViewRegion.rect(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 10.3, y: 40), viewport: viewport) == nil)
    }
}

struct CroppedStateTests {
    @Test func aCropShowsTheSelectionAtTheSameZoomFromTheTopLeft() {
        let cropped = state.cropped(to: CGRect(x: 3, y: 2, width: 12, height: 5))
        #expect(cropped.zoom == 8)
        #expect(cropped.viewportSize == CGSize(width: 96, height: 40))
        #expect(
            cropped.imageRect(origin: CGPoint(x: 3, y: 2), size: CGSize(width: 12, height: 5))
                == CGRect(x: 0, y: 0, width: 96, height: 40))
    }
}

struct ShortcutRulesTests {
    typealias M = ShortcutRules.Modifiers

    @Test func aShortcutNeedsControlOrOptionWithCommand() {
        #expect(ShortcutRules.isAllowed(M(control: true), isHighFunctionKey: false, allowsLoneFunctionKey: false))
        #expect(
            ShortcutRules.isAllowed(
                M(option: true, command: true), isHighFunctionKey: false, allowsLoneFunctionKey: false))
        #expect(!ShortcutRules.isAllowed(M(command: true), isHighFunctionKey: false, allowsLoneFunctionKey: false))
        #expect(!ShortcutRules.isAllowed(M(option: true), isHighFunctionKey: false, allowsLoneFunctionKey: true))
    }

    @Test func aLoneHighFunctionKeyOnlyWhereTheActionAllowsIt() {
        #expect(ShortcutRules.isAllowed(M(), isHighFunctionKey: true, allowsLoneFunctionKey: true))
        #expect(!ShortcutRules.isAllowed(M(), isHighFunctionKey: true, allowsLoneFunctionKey: false))
        #expect(!ShortcutRules.isAllowed(M(), isHighFunctionKey: false, allowsLoneFunctionKey: true))
        #expect(!ShortcutRules.isAllowed(M(shift: true), isHighFunctionKey: true, allowsLoneFunctionKey: true))
    }
}
