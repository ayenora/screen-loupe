import CoreGraphics
import Foundation

/// How a reference is laid over the live pixels.
enum ReferenceBlend: String, Codable, CaseIterable, Sendable {
    case normal
    /// The absolute difference from the live capture: matching pixels turn black.
    case difference
}

/// A design image laid over the live pixels (docs/product.md, References). Its place and size are
/// source pixels, relative to the Capture Area's top-left corner, so it stays on the pixels it was
/// aligned with while the Viewer pans and zooms.
struct ReferenceLayer: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    /// The image's copy in the project folder.
    var fileName: String
    /// The image's size in its own pixels.
    var imageSize: CGSize
    var origin = CGPoint.zero
    /// Source pixels per image pixel, the same both ways.
    var scale: CGFloat = 1
    var opacity: Double = 0.5
    var blend = ReferenceBlend.normal
    var isVisible = true
    /// Pinned: the mouse in the Viewer passes through it to the layer below, or to the image.
    var isPinned = false

    var frame: CGRect {
        CGRect(origin: origin, size: CGSize(width: imageSize.width * scale, height: imageSize.height * scale))
    }

    /// Whether the mouse in the Viewer can take this layer.
    var isMovable: Bool { isVisible && !isPinned }

    init(id: UUID = UUID(), name: String, fileName: String, imageSize: CGSize, origin: CGPoint = .zero) {
        self.id = id
        self.name = name
        self.fileName = fileName
        self.imageSize = imageSize
        self.origin = origin
    }

    /// A setting that is missing or unreadable (saved by an older or a newer version) keeps its
    /// default, rather than failing the whole project. The image itself is required.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(UUID.self, forKey: .id), name: try c.decode(String.self, forKey: .name),
            fileName: try c.decode(String.self, forKey: .fileName),
            imageSize: try c.decode(CGSize.self, forKey: .imageSize))
        origin = c.value(.origin, or: origin)
        scale = c.value(.scale, or: scale)
        opacity = c.value(.opacity, or: opacity)
        blend = c.value(.blend, or: blend)
        isVisible = c.value(.isVisible, or: isVisible)
        isPinned = c.value(.isPinned, or: isPinned)
    }
}

/// A corner handle of the selected reference, for scaling it.
enum ReferenceCorner: CaseIterable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight

    /// Where this corner is on `rect` (y down).
    func point(of rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    var opposite: ReferenceCorner {
        switch self {
        case .topLeft: .bottomRight
        case .topRight: .bottomLeft
        case .bottomLeft: .topRight
        case .bottomRight: .topLeft
        }
    }
}

/// The reference layers, top first, like layers in an image editor.
struct ReferenceStack: Codable, Equatable, Sendable {
    static let limit = 10
    static let scaleRange: ClosedRange<CGFloat> = 0.05...64

    /// Top first: the first layer is drawn last, over all the others.
    var layers: [ReferenceLayer] = []
    var selectedID: UUID?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // An unreadable layer is dropped; the others stay.
        layers = c.value(.layers, or: [Lenient<ReferenceLayer>]()).compactMap(\.value)
        selectedID = c.value(.selectedID, or: nil)
    }

    var canAdd: Bool { layers.count < Self.limit }

    var selected: ReferenceLayer? { layers.first { $0.id == selectedID } }

    /// Adds a layer on top and selects it. Returns `false` at the limit.
    @discardableResult
    mutating func add(_ layer: ReferenceLayer) -> Bool {
        guard canAdd else { return false }
        layers.insert(layer, at: 0)
        selectedID = layer.id
        return true
    }

    mutating func remove(_ id: UUID) {
        layers.removeAll { $0.id == id }
        if selectedID == id { selectedID = layers.first?.id }
    }

    /// Moves the layers at `offsets` to before `destination`, as a list's drag-to-reorder does.
    mutating func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let moving = offsets.map { layers[$0] }
        let before = offsets.filter { $0 < destination }.count
        layers = layers.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        layers.insert(contentsOf: moving, at: destination - before)
    }

    mutating func update(_ id: UUID, _ change: (inout ReferenceLayer) -> Void) {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return }
        change(&layers[index])
    }

    /// The Capture Area's top-left corner moved by `shift` source pixels (its left or top edge was
    /// dragged): every layer stays on the pixels it was aligned with, as the image does, so its X
    /// and Y from the new corner change.
    mutating func followAreaOrigin(shift: CGPoint) {
        for index in layers.indices {
            layers[index].origin = CGPoint(
                x: layers[index].origin.x - shift.x, y: layers[index].origin.y - shift.y)
        }
    }

    /// The layer the mouse takes at `point` (source pixels): the topmost visible, unpinned one
    /// under it. Pinned and hidden layers let the mouse through.
    func movableLayer(at point: CGPoint) -> UUID? {
        layers.first { $0.isMovable && $0.frame.contains(point) }?.id
    }

    // MARK: Editing

    /// `layer` dragged by `delta` source pixels from where the drag started; whole pixels.
    static func moved(_ layer: ReferenceLayer, from start: CGPoint, by delta: CGPoint) -> ReferenceLayer {
        var moved = layer
        moved.origin = CGPoint(x: (start.x + delta.x).rounded(), y: (start.y + delta.y).rounded())
        return moved
    }

    /// `layer` scaled by dragging `corner` to `point` (source pixels): the opposite corner stays,
    /// and so do the proportions.
    static func scaled(_ layer: ReferenceLayer, corner: ReferenceCorner, to point: CGPoint) -> ReferenceLayer {
        guard layer.imageSize.width > 0, layer.imageSize.height > 0 else { return layer }
        let fixed = corner.opposite.point(of: layer.frame)
        let scale = max(
            abs(point.x - fixed.x) / layer.imageSize.width, abs(point.y - fixed.y) / layer.imageSize.height)
        var scaled = layer
        scaled.scale = min(max(scale, scaleRange.lowerBound), scaleRange.upperBound)
        let size = scaled.frame.size
        let left = corner == .topLeft || corner == .bottomLeft
        let top = corner == .topLeft || corner == .topRight
        scaled.origin = CGPoint(x: left ? fixed.x - size.width : fixed.x, y: top ? fixed.y - size.height : fixed.y)
        return scaled
    }
}
