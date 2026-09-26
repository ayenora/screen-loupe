import Foundation
import Testing

struct ScreenshotNameTests {
    /// 2026-09-27 14:20:05 UTC.
    private let date: Date = {
        var components = DateComponents(year: 2026, month: 9, day: 27, hour: 14, minute: 20, second: 5)
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }()
    private let utc = TimeZone(identifier: "UTC")!

    @Test func theViewersNamesAreUnchanged() {
        #expect(
            ScreenshotName.fileName(kind: "View", style: .macOS, date: date, timeZone: utc)
                == "Screen Loupe View 2026-09-27 at 14.20.05.png")
        #expect(
            ScreenshotName.fileName(kind: "Source", style: .compact, date: date, timeZone: utc)
                == "ScreenLoupe-Source-20260927-142005.png")
    }

    @Test func aStudioPictureAddsItsPixelsAndItsFormatsExtension() {
        let size = PixelSize(width: 2880, height: 1800)
        let names = StudioOutput.Format.allCases.map {
            ScreenshotName.fileName(
                kind: "Screenshot", style: .macOS, size: size, fileExtension: $0.fileExtension, date: date,
                timeZone: utc)
        }
        #expect(
            names == [
                "Screen Loupe Screenshot 2026-09-27 at 14.20.05 2880×1800.png",
                "Screen Loupe Screenshot 2026-09-27 at 14.20.05 2880×1800.jpg",
                "Screen Loupe Screenshot 2026-09-27 at 14.20.05 2880×1800.heic",
            ])
    }

    @Test func theCompactStyleWritesThePixelsWithAnX() {
        #expect(
            ScreenshotName.fileName(
                kind: "Screenshot", style: .compact, size: PixelSize(width: 1441, height: 901), fileExtension: "heic",
                date: date, timeZone: utc) == "ScreenLoupe-Screenshot-20260927-142005-1441x901.heic")
    }

    @Test func theTimeIsTheTimeZonesWallClock() {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        #expect(
            ScreenshotName.fileName(kind: "View", style: .macOS, date: date, timeZone: tokyo)
                == "Screen Loupe View 2026-09-27 at 23.20.05.png")
        let later = date.addingTimeInterval(10 * 3600)
        #expect(
            ScreenshotName.fileName(kind: "View", style: .compact, date: later, timeZone: tokyo)
                == "ScreenLoupe-View-20260928-092005.png")
    }
}
