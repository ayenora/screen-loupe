import CoreGraphics
import Foundation
import Testing

struct RecentCaptureArchivePixelTests {
    /// `height` rows of `width` BGRA pixels, `bytesPerRow` apart, every byte different from its
    /// neighbours, alpha 0 and 255 among them.
    private func pixels(width: Int, height: Int, bytesPerRow: Int) -> [UInt8] {
        (0..<bytesPerRow * height).map { UInt8(truncatingIfNeeded: $0 &* 131 &+ 7) }
    }

    /// The PNG of `bytes` read back into rows `outRow` apart; `nil` when either step fails.
    private func roundTrip(
        _ bytes: [UInt8], width: Int, height: Int, bytesPerRow: Int, space: CGColorSpace, outRow: Int
    ) -> [UInt8]? {
        let png = bytes.withUnsafeBytes {
            RecentCaptureArchive.pngData(
                bgra: $0.baseAddress!, width: width, height: height, bytesPerRow: bytesPerRow, space: space)
        }
        guard let png, let image = RecentCaptureArchive.image(png: png),
            image.width == width, image.height == height
        else { return nil }
        var out = [UInt8](repeating: 0, count: outRow * height)
        let copied = out.withUnsafeMutableBytes {
            RecentCaptureArchive.copyPixels(of: image, into: $0.baseAddress!, bytesPerRow: outRow)
        }
        return copied ? out : nil
    }

    private func rows(_ bytes: [UInt8], width: Int, height: Int, bytesPerRow: Int) -> [[UInt8]] {
        (0..<height).map { Array(bytes[$0 * bytesPerRow..<$0 * bytesPerRow + width * 4]) }
    }

    @Test(
        arguments: [CGColorSpace.sRGB, CGColorSpace.displayP3, CGColorSpace.adobeRGB1998, CGColorSpace.itur_2020]
            as [String])
    func everyByteComesBack(spaceName: String) throws {
        let space = try #require(CGColorSpace(name: spaceName as CFString))
        // Rows padded as a pixel buffer's are, read back into rows of another length.
        let (width, height, bytesPerRow) = (37, 5, 160)
        let bytes = pixels(width: width, height: height, bytesPerRow: bytesPerRow)
        let back = try #require(
            roundTrip(bytes, width: width, height: height, bytesPerRow: bytesPerRow, space: space, outRow: 152))
        #expect(
            rows(back, width: width, height: height, bytesPerRow: 152)
                == rows(bytes, width: width, height: height, bytesPerRow: bytesPerRow))
    }

    /// A display's own profile, which the PNG's tag may stand in for: the bytes still aren't converted.
    @Test func everyByteComesBackInASpaceWithoutAName() throws {
        let calibrated = try #require(
            CGColorSpace(
                calibratedRGBWhitePoint: [0.9505, 1, 1.089], blackPoint: [0, 0, 0], gamma: [2.2, 2.2, 2.2],
                matrix: [0.4124, 0.2126, 0.0193, 0.3576, 0.7152, 0.1192, 0.1805, 0.0722, 0.9505]))
        let profile = try #require(calibrated.copyICCData())
        let space = try #require(CGColorSpace(iccData: profile))
        let (width, height) = (16, 16)
        let bytes = pixels(width: width, height: height, bytesPerRow: width * 4)
        let back = try #require(
            roundTrip(bytes, width: width, height: height, bytesPerRow: width * 4, space: space, outRow: width * 4))
        #expect(back == bytes)
    }

    /// Transparent pixels keep their colour: the alpha is straight, never premultiplied.
    @Test func transparentPixelsKeepTheirColour() throws {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let bytes: [UInt8] = [10, 20, 30, 0, 200, 100, 50, 1, 1, 2, 3, 128, 255, 255, 255, 255]
        let back = try #require(roundTrip(bytes, width: 4, height: 1, bytesPerRow: 16, space: space, outRow: 16))
        #expect(back == bytes)
    }

    @Test func anOpaquePictureComesBackOpaque() throws {
        let space = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let bytes: [UInt8] = [10, 20, 30, 255, 200, 100, 50, 255]
        let back = try #require(roundTrip(bytes, width: 1, height: 2, bytesPerRow: 4, space: space, outRow: 4))
        #expect(back == bytes)
    }

    @Test func somethingThatIsNotAPNGReadsAsNothing() {
        #expect(RecentCaptureArchive.image(png: Data("not a picture".utf8)) == nil)
        #expect(RecentCaptureArchive.image(png: Data()) == nil)
    }
}

struct RecentCaptureArchiveColorSpaceTests {
    private func throughJSON(
        _ saved: RecentCaptureArchive.SavedColorSpace
    ) throws
        -> RecentCaptureArchive.SavedColorSpace
    {
        try JSONDecoder().decode(
            RecentCaptureArchive.SavedColorSpace.self, from: JSONEncoder().encode(saved))
    }

    @Test(arguments: [CGColorSpace.sRGB, CGColorSpace.displayP3, CGColorSpace.genericRGBLinear] as [String])
    func aNamedSpaceComesBackByName(spaceName: String) throws {
        let space = try #require(CGColorSpace(name: spaceName as CFString))
        let saved = try throughJSON(try #require(RecentCaptureArchive.SavedColorSpace(space)))
        #expect(saved.iccProfile == nil)
        let back = try #require(saved.space)
        #expect(back.name as String? == spaceName)
        #expect(back == space)
    }

    /// A display's space has no name: its whole profile comes back, byte for byte, as ImageIO's PNG
    /// tag may not keep it.
    @Test func aSpaceWithoutANameComesBackAsItsProfile() throws {
        let calibrated = try #require(
            CGColorSpace(
                calibratedRGBWhitePoint: [0.9505, 1, 1.089], blackPoint: [0, 0, 0], gamma: [1.9, 2.1, 2.3],
                matrix: [0.43, 0.22, 0.02, 0.37, 0.71, 0.13, 0.15, 0.07, 0.94]))
        let calibratedProfile = try #require(calibrated.copyICCData())
        let display = try #require(CGColorSpace(iccData: calibratedProfile))
        #expect(display.name == nil)
        let profile = try #require(display.copyICCData() as Data?)
        let saved = try throughJSON(try #require(RecentCaptureArchive.SavedColorSpace(display)))
        #expect(saved.name == nil)
        #expect(saved.iccProfile == profile)
        let back = try #require(saved.space)
        #expect(back.copyICCData() as Data? == profile)
        // Its colours mean the same.
        let xyz = try #require(CGColorSpace(name: CGColorSpace.genericXYZ))
        let color = { (space: CGColorSpace) in
            CGColor(colorSpace: space, components: [0.2, 0.6, 0.9, 1])?
                .converted(to: xyz, intent: .relativeColorimetric, options: nil)?.components
        }
        #expect(color(back) == color(display))
    }

    @Test func anUnknownNameOrABrokenProfileMakesNoSpace() {
        var saved = RecentCaptureArchive.SavedColorSpace(CGColorSpace(name: CGColorSpace.sRGB)!)!
        saved.name = "kCGColorSpaceFromTheFuture"
        #expect(saved.space == nil)
        saved.name = nil
        saved.iccProfile = Data("not a profile".utf8)
        #expect(saved.space == nil)
    }

    @Test func aSpaceThatIsNotRGBMakesNoSpace() throws {
        let gray = try #require(CGColorSpace(name: CGColorSpace.genericGrayGamma2_2))
        let saved = try #require(RecentCaptureArchive.SavedColorSpace(gray))
        #expect(saved.space == nil)
    }
}

struct RecentCaptureArchiveIndexTests {
    typealias Archive = RecentCaptureArchive

    private let snapshot = Archive.Entry(
        id: UUID(), name: "Snapshot", date: Date(timeIntervalSince1970: 1_790_000_000.5), isFile: false,
        zoom: 8, offset: CGPoint(x: -120.5, y: 36), selection: CGRect(x: 3, y: 4, width: 50, height: 60),
        isLinked: true,
        layout: FrameLayout(
            size: PixelSize(width: 300, height: 200), imageOrigin: CGPoint(x: 40, y: 0),
            imageSize: PixelSize(width: 260, height: 200), scale: 2),
        colorSpace: .init(CGColorSpace(name: CGColorSpace.displayP3)!))

    private let file = Archive.Entry(
        id: UUID(), name: "photo.png", date: Date(timeIntervalSince1970: 1_790_000_100), isFile: true,
        zoom: nil, offset: .zero, selection: nil, isLinked: false,
        layout: FrameLayout(image: PixelSize(width: 640, height: 480)), colorSpace: nil)

    private func decode(_ json: String) throws -> Archive.Index {
        try JSONDecoder().decode(Archive.Index.self, from: Data(json.utf8))
    }

    @Test func theIndexComesBackAsKept() throws {
        let index = Archive.Index(entries: [snapshot, file], shownID: snapshot.id)
        let back = try JSONDecoder().decode(Archive.Index.self, from: JSONEncoder().encode(index))
        #expect(back == index)
        #expect(back.entries[0].layout?.imageOrigin == CGPoint(x: 40, y: 0))
        #expect(back.entries[1].zoom == nil)
    }

    @Test func theLiveViewShownComesBackAsNoShownCapture() throws {
        let index = Archive.Index(entries: [snapshot], shownID: nil)
        let back = try JSONDecoder().decode(Archive.Index.self, from: JSONEncoder().encode(index))
        #expect(back.shownID == nil)
    }

    @Test func aMissingKeyKeepsItsDefault() throws {
        let id = UUID()
        let index = try decode(#"{"entries": [{"id": "\#(id.uuidString)"}]}"#)
        let entry = try #require(index.entries.first)
        #expect(entry.id == id)
        #expect(entry.name == "Snapshot")
        #expect(entry.isFile == false)
        #expect(entry.zoom == nil)
        #expect(entry.offset == .zero)
        #expect(entry.selection == nil)
        #expect(entry.isLinked == false)
        #expect(entry.layout == nil)
        #expect(entry.colorSpace == nil)
        #expect(index.shownID == nil)
    }

    @Test func anUnreadableValueKeepsItsDefaultAndTheRestLoads() throws {
        let id = UUID()
        let index = try decode(
            #"""
            {"entries": [{"id": "\#(id.uuidString)", "name": 7, "zoom": "big", "isLinked": true,
              "layout": {"size": "wide"}, "offset": [5, 6]}], "shownID": "not an id"}
            """#)
        let entry = try #require(index.entries.first)
        #expect(entry.name == "Snapshot")
        #expect(entry.zoom == nil)
        #expect(entry.layout == nil)
        #expect(entry.isLinked)
        #expect(entry.offset == CGPoint(x: 5, y: 6))
        #expect(index.shownID == nil)
    }

    @Test func anEntryWithoutAnIdIsDropped() throws {
        let id = UUID()
        let index = try decode(
            #"{"entries": [{"name": "lost"}, {"id": 12}, {"id": "\#(id.uuidString)", "name": "kept"}]}"#)
        #expect(index.entries.map(\.id) == [id])
    }

    @Test func unreadableEntriesMakeAnEmptyList() throws {
        #expect(try decode(#"{"entries": "none"}"#).entries.isEmpty)
        #expect(try decode("{}").entries.isEmpty)
    }

    @Test func aBrokenIndexDoesNotRead() {
        #expect((try? decode("{\"entries\": [")) == nil)
        #expect((try? decode("")) == nil)
    }

    // MARK: What is restored

    @Test func restoresOneOfEachIdUpToTheLimit() {
        let entries = (0..<10).map { _ in file }.enumerated().map { index, entry in
            var entry = entry
            entry.id = UUID()
            entry.name = "\(index)"
            return entry
        }
        let restored = Archive.restorable([entries[0]] + entries, limit: 8)
        #expect(restored.map(\.name) == (0..<8).map { "\($0)" })
    }

    private func entries(_ names: [String]) -> [Archive.Entry] {
        names.map {
            var entry = file
            entry.id = UUID()
            entry.name = $0
            return entry
        }
    }

    /// A capture whose PNG couldn't be read keeps its entry, so its file isn't a stray and the next
    /// launch tries again; captures added since launch are not among the kept ones and stay on top.
    @Test func unlistedCapturesFollowTheList() {
        let listed = entries(["a", "b"])
        let unlisted = entries(["unreadable", "still reading"])
        let fitted = Archive.indexEntries(listed: listed, unlisted: unlisted, order: unlisted.map(\.id), limit: 8)
        #expect(fitted.entries.map(\.name) == ["a", "b", "unreadable", "still reading"])
        #expect(fitted.dropped.isEmpty)
        #expect(Archive.strayFiles(fitted.entries.map { Archive.fileName(for: $0.id) }, kept: fitted.entries).isEmpty)
    }

    /// A save while the kept captures are read, with an old one shown: each keeps its place, so the
    /// shown one isn't moved up by a save or a quit before the rest came in.
    @Test func unlistedCapturesKeepTheirPlacesAmongTheKeptOnes() {
        let kept = entries(["k1", "k2", "shown", "k4"])
        let new = entries(["new"])
        let listed = new + [kept[2]]
        let unlisted = [kept[0], kept[1], kept[3]]
        let fitted = Archive.indexEntries(listed: listed, unlisted: unlisted, order: kept.map(\.id), limit: 8)
        #expect(fitted.entries.map(\.name) == ["new", "k1", "k2", "shown", "k4"])
        #expect(fitted.dropped.isEmpty)
    }

    /// Never past the limit: the list's captures all stay, and the oldest unlisted ones go.
    @Test func unlistedCapturesArePushedOutPastTheLimit() {
        let listed = entries(["1", "2", "3", "4", "5", "6", "7"])
        let unlisted = entries(["x", "y", "z"])
        let fitted = Archive.indexEntries(listed: listed, unlisted: unlisted, order: unlisted.map(\.id), limit: 8)
        #expect(fitted.entries.map(\.name) == ["1", "2", "3", "4", "5", "6", "7", "x"])
        #expect(fitted.dropped.map(\.name) == ["y", "z"])
    }

    /// An old shown capture stays; the unlisted ones older than it go first, then the newer ones.
    @Test func theListedCapturesStayWhateverTheirAge() {
        let kept = entries(["k1", "k2", "shown", "k4"])
        let new = entries(["n1", "n2", "n3", "n4", "n5", "n6"])
        let fitted = Archive.indexEntries(
            listed: new + [kept[2]], unlisted: [kept[0], kept[1], kept[3]], order: kept.map(\.id), limit: 8)
        #expect(fitted.entries.map(\.name) == ["n1", "n2", "n3", "n4", "n5", "n6", "k1", "shown"])
        #expect(fitted.dropped.map(\.name) == ["k2", "k4"])
    }

    @Test func aFullListLeavesNoRoomForUnlistedCaptures() {
        let listed = entries((1...8).map { "\($0)" })
        let unlisted = entries(["x"])
        let fitted = Archive.indexEntries(listed: listed, unlisted: unlisted, order: unlisted.map(\.id), limit: 8)
        #expect(fitted.entries.count == 8)
        #expect(fitted.dropped.map(\.name) == ["x"])
    }

    @Test func strayFilesAreThoseTheIndexDoesNotName() {
        let files = [
            Archive.indexName, Archive.fileName(for: snapshot.id), Archive.fileName(for: file.id), "old.png",
            "\(UUID().uuidString).png",
        ]
        #expect(Archive.strayFiles(files, kept: [snapshot]) == [files[2], files[3], files[4]])
        #expect(Archive.strayFiles([Archive.indexName], kept: []).isEmpty)
    }

    @Test func aFileIsNamedByItsCapture() {
        let id = UUID()
        #expect(Archive.fileName(for: id) == "\(id.uuidString).png")
    }

    // MARK: Layout

    @Test func aLayoutThatFitsItsPixelsIsKept() {
        let saved = snapshot.layout
        #expect(Archive.layout(saved, pixels: PixelSize(width: 260, height: 200)) == saved)
    }

    @Test func aLayoutThatDoesNotFitItsPixelsIsTheWholePicture() {
        let pixels = PixelSize(width: 260, height: 200)
        let whole = FrameLayout(image: pixels)
        var layout = snapshot.layout!
        #expect(Archive.layout(nil, pixels: pixels) == whole)
        let wider = PixelSize(width: 261, height: 200)
        #expect(Archive.layout(layout, pixels: wider) == FrameLayout(image: wider))
        layout.imageOrigin = CGPoint(x: 41, y: 0)
        #expect(Archive.layout(layout, pixels: pixels) == whole)
        layout.imageOrigin = CGPoint(x: -1, y: 0)
        #expect(Archive.layout(layout, pixels: pixels) == whole)
        layout.imageOrigin = CGPoint(x: 40, y: 0)
        layout.scale = 0
        #expect(Archive.layout(layout, pixels: pixels) == whole)
    }
}
