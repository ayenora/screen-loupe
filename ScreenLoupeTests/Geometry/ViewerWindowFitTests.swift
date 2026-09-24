import CoreGraphics
import Testing

struct ViewerWindowFitTests {
    /// A 1440 × 875 pt visible frame, as on a MacBook with the menu bar and Dock.
    private let visible = CGRect(x: 0, y: 70, width: 1440, height: 875)
    private let chrome = CGSize(width: 0, height: 52)
    private let minSize = CGSize(width: 300, height: 200)

    private func fit(_ image: CGSize, window: CGRect, scale: CGFloat = 2) -> CGRect {
        ViewerWindowFit.frame(
            imageSize: image, chrome: chrome, window: window, visible: visible, minSize: minSize, scale: scale)
    }

    @Test func sizesToImagePlusChromeKeepingTheTopLeftCorner() {
        let frame = fit(CGSize(width: 400, height: 300), window: CGRect(x: 100, y: 400, width: 600, height: 500))
        #expect(frame == CGRect(x: 100, y: 548, width: 400, height: 352))
    }

    @Test func neverGrowsBeyondTheVisibleFrame() {
        let frame = fit(CGSize(width: 5000, height: 4000), window: CGRect(x: 100, y: 400, width: 600, height: 500))
        #expect(frame == visible)
    }

    @Test func movesLeftAndDownToStayOnScreen() {
        // The top-left corner is near the right and top edges; the new size wouldn't fit there.
        let frame = fit(CGSize(width: 800, height: 600), window: CGRect(x: 1000, y: 700, width: 300, height: 245))
        #expect(frame == CGRect(x: 640, y: 293, width: 800, height: 652))
        #expect(visible.contains(frame))
    }

    @Test func movesUpWhenTheBottomWouldLeaveTheScreen() {
        let frame = fit(CGSize(width: 400, height: 700), window: CGRect(x: 100, y: 80, width: 400, height: 300))
        #expect(frame.minY == visible.minY)
        #expect(frame.height == CGFloat(752))
    }

    @Test func keepsTheMinimumSize() {
        let frame = fit(CGSize(width: 50, height: 40), window: CGRect(x: 100, y: 400, width: 600, height: 500))
        #expect(frame.size == minSize)
    }

    @Test func roundsTheImageUpToWholeDevicePixels() {
        // 220.3 pt on a 2× display is 440.6 px; the image area needs 441 px = 220.5 pt.
        let frame = fit(CGSize(width: 320.3, height: 300), window: CGRect(x: 100, y: 400, width: 600, height: 500))
        #expect(frame.width == CGFloat(320.5))
    }

    @Test func worksOnADisplayLeftOfThePrimary() {
        let left = CGRect(x: -1920, y: 0, width: 1920, height: 1055)
        let frame = ViewerWindowFit.frame(
            imageSize: CGSize(width: 800, height: 600), chrome: chrome,
            window: CGRect(x: -500, y: 600, width: 400, height: 300), visible: left, minSize: minSize, scale: 1)
        #expect(left.contains(frame))
        #expect(frame.maxX == left.maxX)
    }
}
