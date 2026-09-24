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

    @Test func aStackRoundTrips() throws {
        var stack = ReferenceStack()
        stack.add(ReferenceLayer(name: "a", fileName: "a.png", imageSize: CGSize(width: 10, height: 10)))
        stack.update(stack.layers[0].id) { $0.blend = .difference }
        let decoded = try JSONDecoder().decode(ReferenceStack.self, from: JSONEncoder().encode(stack))
        #expect(decoded == stack)
    }
}
