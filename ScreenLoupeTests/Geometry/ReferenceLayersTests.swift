import CoreGraphics
import Foundation
import Testing

struct ReferenceLayersTests {
    private func layer(
        _ name: String, origin: CGPoint = .zero, size: CGSize = CGSize(width: 100, height: 50)
    )
        -> ReferenceLayer
    {
        ReferenceLayer(name: name, fileName: "\(name).png", imageSize: size, origin: origin)
    }

    @Test func addsOnTopUpToTheLimit() {
        var stack = ReferenceStack()
        for index in 0..<ReferenceStack.limit {
            let added = stack.add(layer("\(index)"))
            #expect(added)
        }
        let extra = stack.add(layer("extra"))
        #expect(!extra)
        #expect(stack.layers.count == ReferenceStack.limit)
        #expect(stack.layers.first?.name == "9")
        #expect(stack.selected?.name == "9")
    }

    @Test func theMouseTakesTheTopmostMovableLayer() {
        var stack = ReferenceStack()
        stack.add(layer("bottom"))
        stack.add(layer("top"))
        let top = stack.layers[0].id
        let bottom = stack.layers[1].id
        #expect(stack.movableLayer(at: CGPoint(x: 10, y: 10)) == top)
        stack.update(top) { $0.isPinned = true }
        #expect(stack.movableLayer(at: CGPoint(x: 10, y: 10)) == bottom)
        stack.update(bottom) { $0.isVisible = false }
        #expect(stack.movableLayer(at: CGPoint(x: 10, y: 10)) == nil)
    }

    @Test func missesOutsideEveryLayer() {
        var stack = ReferenceStack()
        stack.add(layer("a", origin: CGPoint(x: 20, y: 20)))
        #expect(stack.movableLayer(at: CGPoint(x: 10, y: 10)) == nil)
    }

    @Test func movesInWholeSourcePixels() {
        let moved = ReferenceStack.moved(layer("a"), from: CGPoint(x: 3, y: 4), by: CGPoint(x: 2.4, y: -1.6))
        #expect(moved.origin == CGPoint(x: 5, y: 2))
    }

    @Test func scalingKeepsTheOppositeCornerAndProportions() {
        let original = layer("a", origin: CGPoint(x: 10, y: 10))
        // Dragging the bottom-right corner from (110, 60) to (210, 70): width doubles, height follows.
        let scaled = ReferenceStack.scaled(original, corner: .bottomRight, to: CGPoint(x: 210, y: 70))
        #expect(scaled.scale == 2)
        #expect(scaled.frame == CGRect(x: 10, y: 10, width: 200, height: 100))
    }

    @Test func scalingFromTheTopLeftKeepsTheBottomRight() {
        let original = layer("a", origin: CGPoint(x: 10, y: 10))
        let scaled = ReferenceStack.scaled(original, corner: .topLeft, to: CGPoint(x: 60, y: 30))
        #expect(scaled.scale == CGFloat(0.6))
        #expect(scaled.frame.maxX == 110)
        #expect(scaled.frame.maxY == 60)
    }

    @Test func removingTheSelectedLayerSelectsTheTopOne() {
        var stack = ReferenceStack()
        stack.add(layer("a"))
        stack.add(layer("b"))
        stack.remove(stack.layers[0].id)
        #expect(stack.selected?.name == "a")
    }

    @Test func reordersLikeAListDrag() {
        var stack = ReferenceStack()
        for name in ["c", "b", "a"] { stack.add(layer(name)) }
        // a b c → drag a below c.
        stack.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(stack.layers.map(\.name) == ["b", "c", "a"])
        stack.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(stack.layers.map(\.name) == ["a", "b", "c"])
    }

    @Test func layersStayOnTheirPixelsWhenTheAreasLeftOrTopEdgeIsDragged() {
        var stack = ReferenceStack()
        stack.add(layer("a", origin: CGPoint(x: 10, y: 20)))
        stack.add(layer("b", origin: CGPoint(x: -5, y: 0)))
        // The left edge dragged 4 px left, the top edge 3 px down.
        stack.followAreaOrigin(shift: CGPoint(x: -4, y: 3))
        #expect(stack.layers.map(\.origin) == [CGPoint(x: -1, y: -3), CGPoint(x: 14, y: 17)])
    }
}

struct ReferenceLayersCodingTests {
    @Test func aLayerSavedWithoutNewerKeysKeepsTheirDefaults() throws {
        let json = """
            {"id":"8C1F5C4E-8A57-4E61-9F2E-1B2B3C4D5E6F","name":"a.png","fileName":"a.png","imageSize":[100,50]}
            """
        let layer = try JSONDecoder().decode(ReferenceLayer.self, from: Data(json.utf8))
        #expect(layer.opacity == 0.5)
        #expect(layer.scale == 1)
        #expect(layer.isVisible)
        #expect(!layer.isPinned)
    }

    @Test func anUnknownValueCostsOnlyItsOwnSetting() throws {
        let json = """
            {"id":"8C1F5C4E-8A57-4E61-9F2E-1B2B3C4D5E6F","name":"a.png","fileName":"a.png","imageSize":[100,50],
             "blend":"multiply","opacity":"half","scale":2,"isPinned":true}
            """
        let layer = try JSONDecoder().decode(ReferenceLayer.self, from: Data(json.utf8))
        #expect(layer.blend == .normal)
        #expect(layer.opacity == 0.5)
        #expect(layer.scale == 2)
        #expect(layer.isPinned)
    }

    @Test func anUnreadableLayerIsDroppedAndTheOthersStay() throws {
        let json = """
            {"layers":[
              {"id":"8C1F5C4E-8A57-4E61-9F2E-1B2B3C4D5E6F","name":"a.png","fileName":"a.png","imageSize":[10,10]},
              {"id":"not a uuid","name":"b.png","fileName":"b.png","imageSize":[10,10]}
            ],"selectedID":"8C1F5C4E-8A57-4E61-9F2E-1B2B3C4D5E6F"}
            """
        let stack = try JSONDecoder().decode(ReferenceStack.self, from: Data(json.utf8))
        #expect(stack.layers.map(\.name) == ["a.png"])
        #expect(stack.selected?.name == "a.png")
    }

    @Test func aStackRoundTrips() throws {
        var stack = ReferenceStack()
        stack.add(ReferenceLayer(name: "a", fileName: "a.png", imageSize: CGSize(width: 10, height: 10)))
        stack.update(stack.layers[0].id) { $0.blend = .difference }
        let decoded = try JSONDecoder().decode(ReferenceStack.self, from: JSONEncoder().encode(stack))
        #expect(decoded == stack)
    }
}

struct PictureInAreaTests {
    private let layer = ReferenceLayer(
        name: "design.png", fileName: "a.png", imageSize: CGSize(width: 40, height: 30),
        origin: CGPoint(x: 120, y: 70))

    private func picture(_ origin: CGPoint) -> CGRect {
        PictureInArea.pictureRect(layer.frame, pictureOrigin: origin)
    }

    /// The live view, frozen or not, is the whole area: the layer shows at its place in it.
    @Test func overTheLiveViewALayerShowsAtItsPlace() {
        #expect(picture(.zero) == layer.frame)
    }

    /// A snapshot of the part from (100, 50): its pixel (20, 20) is the area's (120, 70).
    @Test func overASnapshotALayerShowsOnTheSamePixels() {
        #expect(picture(CGPoint(x: 100, y: 50)) == CGRect(x: 20, y: 20, width: 40, height: 30))
    }

    /// A snapshot kept before its place was recorded, and an image, sit at the area's corner.
    @Test func overAPictureWithoutAPlaceALayerShowsAtItsPlace() {
        let origin = RecentCaptureArchive.areaOrigin(entry(isFile: false, areaOrigin: nil))
        #expect(picture(origin) == layer.frame)
        let file = RecentCaptureArchive.areaOrigin(entry(isFile: true, areaOrigin: CGPoint(x: 9, y: 9)))
        #expect(file == .zero)
    }

    @Test func aKeptSnapshotSitsWhereItWasTaken() {
        #expect(
            RecentCaptureArchive.areaOrigin(entry(isFile: false, areaOrigin: CGPoint(x: 100, y: 50)))
                == CGPoint(x: 100, y: 50))
    }

    @Test func aPointOverThePictureIsThePointInTheArea() {
        #expect(
            PictureInArea.areaPoint(CGPoint(x: 25, y: 30), pictureOrigin: CGPoint(x: 100, y: 50))
                == CGPoint(x: 125, y: 80))
        #expect(PictureInArea.areaPoint(CGPoint(x: 25, y: 30), pictureOrigin: .zero) == CGPoint(x: 25, y: 30))
    }

    /// The mouse over a snapshot takes the layer on those pixels, not the one at the same place in the picture.
    @Test func theMouseOverASnapshotTakesTheLayerOnItsPixels() {
        var stack = ReferenceStack()
        stack.add(layer)
        let origin = CGPoint(x: 100, y: 50)
        #expect(
            stack.movableLayer(at: PictureInArea.areaPoint(CGPoint(x: 30, y: 30), pictureOrigin: origin)) == layer.id)
        #expect(stack.movableLayer(at: PictureInArea.areaPoint(CGPoint(x: 130, y: 80), pictureOrigin: origin)) == nil)
    }

    /// Dragged over a snapshot, the layer moves in the area by the drag: back on the live view it
    /// shows on the pixels it was dropped on over the snapshot.
    @Test func aLayerDraggedOverASnapshotKeepsItsPlaceBackLive() {
        let origin = CGPoint(x: 100, y: 50)
        let moved = ReferenceStack.moved(layer, from: layer.origin, by: CGPoint(x: 5, y: -3))
        #expect(PictureInArea.pictureRect(moved.frame, pictureOrigin: origin).origin == CGPoint(x: 25, y: 17))
        #expect(PictureInArea.pictureRect(moved.frame, pictureOrigin: .zero).origin == CGPoint(x: 125, y: 67))
    }

    /// A corner dragged over a snapshot scales about the opposite corner's place in the area.
    @Test func aCornerDraggedOverASnapshotScalesInTheArea() {
        let origin = CGPoint(x: 100, y: 50)
        // The bottom-right corner to the snapshot's (100, 80): the area's (200, 130).
        let point = PictureInArea.areaPoint(CGPoint(x: 100, y: 80), pictureOrigin: origin)
        let scaled = ReferenceStack.scaled(layer, corner: .bottomRight, to: point)
        #expect(scaled.origin == layer.origin)
        #expect(scaled.frame == CGRect(x: 120, y: 70, width: 80, height: 60))
    }

    private func entry(isFile: Bool, areaOrigin: CGPoint?) -> RecentCaptureArchive.Entry {
        RecentCaptureArchive.Entry(
            id: UUID(), name: "Snapshot", date: Date(), isFile: isFile, zoom: nil, offset: .zero, selection: nil,
            isLinked: false, layout: nil, colorSpace: nil, areaOrigin: areaOrigin)
    }
}

struct ReferenceStrayFilesTests {
    private func layer(_ file: String) -> ReferenceLayer {
        ReferenceLayer(name: file, fileName: file, imageSize: CGSize(width: 1, height: 1))
    }

    /// A copy written as the app quit, before its layer was added, is a stray.
    @Test func filesNoLayerUsesAreStrays() {
        let stray = ReferenceStack.strayFiles(
            ["project.json", "A.png", "B.tiff", "C.tiff"], layers: [layer("A.png"), layer("C.tiff")],
            projectFile: "project.json")
        #expect(stray == ["B.tiff"])
    }

    @Test func theProjectFileIsNeverAStray() {
        #expect(ReferenceStack.strayFiles(["project.json"], layers: [], projectFile: "project.json").isEmpty)
    }

    @Test func withoutLayersEveryImageIsAStray() {
        #expect(
            ReferenceStack.strayFiles(["project.json", "A.png"], layers: [], projectFile: "project.json") == ["A.png"])
    }

    @Test func aLayerWhoseFileIsGoneMakesNoStray() {
        #expect(
            ReferenceStack.strayFiles(["project.json"], layers: [layer("gone.png")], projectFile: "project.json")
                .isEmpty)
    }
}
