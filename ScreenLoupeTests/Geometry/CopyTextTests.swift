import CoreGraphics
import Testing

/// The layer's frame is in the image area's points, y down, as the drawable pixels it comes from.
struct CopyTextOverlayFrameTests {
    private func state(
        zoom: CGFloat, offset: CGPoint, content: CGSize = CGSize(width: 200, height: 100)
    )
        -> ZoomPanState
    {
        ZoomPanState(zoom: zoom, offset: offset, contentSize: content, viewportSize: CGSize(width: 800, height: 600))
    }

    private let image = PixelSize(width: 200, height: 100)

    @Test func atOneToOneTheLayerCoversTheImage() {
        let frame = CopyText.overlayFrame(
            state: state(zoom: 1, offset: .zero), imageOrigin: .zero, imageSize: image, drawableScale: 1)
        #expect(frame == CGRect(x: 0, y: 0, width: 200, height: 100))
    }

    @Test func zoomAndPanMoveAndScaleItOnRetina() {
        // 4 × 200 = 800 drawable pixels, 400 points; the top-left at (-100, -50) drawable pixels.
        let frame = CopyText.overlayFrame(
            state: state(zoom: 4, offset: CGPoint(x: -100, y: -50)), imageOrigin: .zero, imageSize: image,
            drawableScale: 2)
        #expect(frame == CGRect(x: -50, y: -25, width: 400, height: 200))
    }

    @Test func aCentredImageSitsWhereItIsCentred() {
        let frame = CopyText.overlayFrame(
            state: state(zoom: 2, offset: CGPoint(x: 200, y: 200)), imageOrigin: .zero, imageSize: image,
            drawableScale: 1)
        #expect(frame == CGRect(x: 200, y: 200, width: 400, height: 200))
    }

    @Test func fractionalZoomKeepsFractionalPoints() {
        let frame = CopyText.overlayFrame(
            state: state(zoom: 0.37, offset: CGPoint(x: 13, y: 7)), imageOrigin: .zero, imageSize: image,
            drawableScale: 2)
        #expect(abs(frame.minX - 6.5) < 1e-9)
        #expect(abs(frame.minY - 3.5) < 1e-9)
        #expect(abs(frame.width - 37) < 1e-9)
        #expect(abs(frame.height - 18.5) < 1e-9)
    }

    @Test func fractionalScaleDividesExactly() {
        // A display scaled to 1.5 drawable pixels per point.
        let frame = CopyText.overlayFrame(
            state: state(zoom: 3, offset: CGPoint(x: -30, y: 15)), imageOrigin: .zero, imageSize: image,
            drawableScale: 1.5)
        #expect(frame == CGRect(x: -20, y: 10, width: 400, height: 200))
    }

    @Test func aFrameThatStartsInsideThePictureStartsThereOnScreen() {
        // An area straddling two displays: the frame's pixels start 50 pixels into the picture.
        let frame = CopyText.overlayFrame(
            state: state(zoom: 3, offset: CGPoint(x: 10, y: 20), content: CGSize(width: 250, height: 120)),
            imageOrigin: CGPoint(x: 50, y: 20), imageSize: image, drawableScale: 1)
        #expect(frame == CGRect(x: 10 + 50 * 3, y: 20 + 20 * 3, width: 600, height: 300))
    }

    @Test func eachPixelLandsWhereTheViewerDrawsIt() {
        let zoomPan = state(zoom: 6, offset: CGPoint(x: -37, y: 11))
        let scale: CGFloat = 2
        let origin = CGPoint(x: 4, y: 9)
        let frame = CopyText.overlayFrame(state: zoomPan, imageOrigin: origin, imageSize: image, drawableScale: scale)
        for pixel in [CGPoint(x: 0, y: 0), CGPoint(x: 17, y: 42), CGPoint(x: 199, y: 99)] {
            let drawn = zoomPan.viewportPoint(forSourcePoint: CGPoint(x: origin.x + pixel.x, y: origin.y + pixel.y))
            #expect(abs(frame.minX + pixel.x * zoomPan.zoom / scale - drawn.x / scale) < 1e-9)
            #expect(abs(frame.minY + pixel.y * zoomPan.zoom / scale - drawn.y / scale) < 1e-9)
        }
    }

    @Test func aMissingScaleCountsAsOne() {
        let frame = CopyText.overlayFrame(
            state: state(zoom: 2, offset: .zero), imageOrigin: .zero, imageSize: PixelSize(width: 10, height: 10),
            drawableScale: 0)
        #expect(frame == CGRect(x: 0, y: 0, width: 20, height: 20))
    }

    @Test func farZoomReachesWellPastTheArea() {
        let frame = CopyText.overlayFrame(
            state: state(zoom: 64, offset: CGPoint(x: -6400, y: -3200)), imageOrigin: .zero, imageSize: image,
            drawableScale: 2)
        #expect(frame == CGRect(x: -3200, y: -1600, width: 6400, height: 3200))
    }

    @Test func anImageWithNoPixelsHasAnEmptyLayer() {
        let frame = CopyText.overlayFrame(
            state: state(zoom: 8, offset: CGPoint(x: 5, y: 5)), imageOrigin: .zero,
            imageSize: PixelSize(width: 0, height: 0), drawableScale: 2)
        #expect(frame == CGRect(x: 2.5, y: 2.5, width: 0, height: 0))
    }
}

struct CopyTextPillTests {
    @Test func overTheFrozenLiveViewItSaysFrozen() {
        #expect(CopyText.pillText(picture: nil) == "Text · Frozen · Esc clears, then leaves")
    }

    @Test func overARecentCaptureOrAnImageItNamesIt() {
        #expect(CopyText.pillText(picture: "Capture 2 of 8") == "Text · Capture 2 of 8 · Esc clears, then leaves")
        #expect(CopyText.pillText(picture: "photo.png") == "Text · photo.png · Esc clears, then leaves")
    }
}

struct CopyTextToastTests {
    @Test func aShortTextShowsWholeInQuotes() {
        #expect(CopyText.toast(for: "Continue") == "“Continue” copied")
    }

    @Test func lineBreaksAndRunsOfSpacesBecomeOneSpace() {
        #expect(CopyText.toast(for: "Sign\nin") == "“Sign in” copied")
        #expect(CopyText.toast(for: "Sign \r\n\t  in") == "“Sign in” copied")
        #expect(CopyText.toast(for: "a\u{2028}b") == "“a b” copied")
    }

    @Test func spacesAroundTheTextAreLeftOut() {
        #expect(CopyText.toast(for: "  \n Continue \n") == "“Continue” copied")
    }

    @Test func nothingButSpacesIsNoText() {
        #expect(CopyText.toast(for: "") == nil)
        #expect(CopyText.toast(for: " ") == nil)
        #expect(CopyText.toast(for: "\n\t \r\n") == nil)
    }

    @Test func textOfExactlyTheLimitIsNotCut() {
        let text = String(repeating: "a", count: CopyText.toastLength)
        #expect(CopyText.toast(for: text) == "“\(text)” copied")
    }

    @Test func longerTextIsCutAtTheEndWithAnEllipsis() {
        let text = String(repeating: "a", count: CopyText.toastLength + 1)
        let shown = String(repeating: "a", count: CopyText.toastLength - 1) + "…"
        #expect(CopyText.toast(for: text) == "“\(shown)” copied")
    }

    @Test func theCutDropsTheSpaceBeforeTheEllipsis() {
        // The last character kept is a space.
        let text = String(repeating: "a", count: CopyText.toastLength - 2) + "  bcd"
        let shown = String(repeating: "a", count: CopyText.toastLength - 2) + "…"
        #expect(CopyText.toast(for: text) == "“\(shown)” copied")
    }

    @Test func theLimitCountsCharactersAsTheyShow() {
        // Each flag is one character of two scalars; an accented letter one of two.
        let flags = String(repeating: "🇺🇦", count: CopyText.toastLength)
        #expect(CopyText.toast(for: flags) == "“\(String(repeating: "🇺🇦", count: CopyText.toastLength))” copied")
        let accents = String(repeating: "e\u{301}", count: CopyText.toastLength + 5)
        let shown = String(repeating: "e\u{301}", count: CopyText.toastLength - 1) + "…"
        #expect(CopyText.toast(for: accents) == "“\(shown)” copied")
    }

    @Test func aLongMultilineTextBecomesOneCutLine() {
        let text = "Pick up\nwhere you\nleft off\nwith your last project"
        let toast = CopyText.toast(for: text)
        #expect(toast == "“Pick up where you left off with…” copied")
        #expect(toast?.contains("\n") == false)
    }
}
