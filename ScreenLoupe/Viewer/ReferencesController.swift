import AppKit
import ImageIO
import Observation
import UniformTypeIdentifiers

/// The reference layers (docs/product.md, References): the stack kept in the project, the images,
/// and the mouse in the Viewer. Points here are drawable pixels, y down, as in `ZoomPanState`.
@MainActor
@Observable
final class ReferencesController {
    enum Part: Equatable {
        case layer(UUID)
        case corner(UUID, ReferenceCorner)
    }

    /// The corner handles of the selected layer.
    static let handleSize: CGFloat = 8

    /// Shown and taking the mouse only while the References panel is open.
    var isActive = false {
        didSet { if isActive != oldValue { onChange?() } }
    }

    /// Off while the eyedropper is active: it comes first, so layers neither take the mouse nor
    /// show their handles.
    @ObservationIgnored var takesMouse = true {
        didSet { if takesMouse != oldValue { onChange?() } }
    }

    /// The panel's content scale, 1 at the side column's narrowest (docs/product.md, References).
    var scale: CGFloat = 1

    var stack: ReferenceStack { project.project.references }

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let project: ProjectStore
    @ObservationIgnored private let zoomPan: ZoomPanController
    /// Decoded images; observed, so thumbnails show once theirs has loaded.
    private var images: [UUID: CGImage] = [:]
    @ObservationIgnored private var loading: Set<UUID> = []
    @ObservationIgnored private var drag: (part: Part, startPoint: CGPoint, startLayer: ReferenceLayer)?

    init(project: ProjectStore, zoomPan: ZoomPanController) {
        self.project = project
        self.zoomPan = zoomPan
    }

    // MARK: The stack

    /// Visible layers bottom first, the order they are drawn in, with their images.
    var drawable: [(layer: ReferenceLayer, image: CGImage)] {
        guard isActive else { return [] }
        return stack.layers.reversed().compactMap { layer in
            guard layer.isVisible, let image = image(for: layer) else { return nil }
            return (layer, image)
        }
    }

    /// The layer's image, or `nil` while it loads. A design image can be large, so it is decoded off
    /// the main thread; the Viewer draws it and the panel shows it once it is there. Past
    /// `ImageBudget` only its top-left part is kept.
    func image(for layer: ReferenceLayer) -> CGImage? {
        if let image = images[layer.id] { return image }
        guard loading.insert(layer.id).inserted else { return nil }
        let url = project.imageURL(for: layer.fileName)
        Task {
            let image = await Self.decodeImage(at: url)
            loading.remove(layer.id)
            guard let image, stack.layers.contains(where: { $0.id == layer.id }) else { return }
            images[layer.id] = image.value
            // A layer imported before the budget was sized by the whole image.
            let size = CGSize(width: image.value.width, height: image.value.height)
            if layer.imageSize != size { update(layer.id) { $0.imageSize = size } }
            onChange?()
        }
        return nil
    }

    @concurrent
    nonisolated private static func decodeImage(at url: URL) async -> UncheckedSendable<CGImage>? {
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, options)
        else { return nil }
        let kept = ImageBudget.fitted(width: image.width, height: image.height)
        guard kept != (image.width, image.height) else { return UncheckedSendable(value: image) }
        return image.cropping(to: CGRect(x: 0, y: 0, width: kept.width, height: kept.height))
            .map { UncheckedSendable(value: $0) }
    }

    func update(_ change: (inout ReferenceStack) -> Void) {
        project.update { change(&$0.references) }
        onChange?()
    }

    func update(_ id: UUID, _ change: (inout ReferenceLayer) -> Void) {
        update { $0.update(id, change) }
    }

    func select(_ id: UUID?) {
        update { $0.selectedID = id }
    }

    func remove(_ id: UUID) {
        guard let layer = stack.layers.first(where: { $0.id == id }) else { return }
        update { $0.remove(id) }
        images[id] = nil
        project.deleteImage(layer.fileName)
    }

    /// The Viewer window, for the open panel's sheet.
    @ObservationIgnored weak var window: NSWindow?

    /// Asks for images and adds each as a layer on top, as many as the limit allows.
    func addFromFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic, .bmp, .gif]
        panel.allowsMultipleSelection = true
        panel.message = "Choose design images to lay over the capture."
        let handle: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let self else { return }
            for url in panel.urls.prefix(ReferenceStack.limit - stack.layers.count) {
                guard let layer = project.importImage(at: url) else { continue }
                update { $0.add(layer) }
            }
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: handle)
        } else {
            handle(panel.runModal())
        }
    }

    // MARK: The mouse in the Viewer

    /// The selected layer's corner handles, in drawable pixels.
    func handles(scale: CGFloat) -> [(corner: ReferenceCorner, rect: CGRect)] {
        guard isActive, takesMouse, let layer = stack.selected, layer.isMovable else { return [] }
        let rect = zoomPan.state.imageRect(origin: layer.origin, size: layer.frame.size)
        let size = Self.handleSize * scale
        return ReferenceCorner.allCases.map { corner in
            let point = corner.point(of: rect)
            return (corner, CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size))
        }
    }

    func part(at point: CGPoint, scale: CGFloat) -> Part? {
        guard isActive, takesMouse else { return nil }
        let grab = 4 * scale
        if let selected = stack.selectedID,
            let handle = handles(scale: scale).first(where: { $0.rect.insetBy(dx: -grab, dy: -grab).contains(point) })
        {
            return .corner(selected, handle.corner)
        }
        let source = zoomPan.state.sourcePoint(forViewportPoint: point)
        return stack.movableLayer(at: source).map(Part.layer)
    }

    /// Takes a press on a layer or a handle, selecting the layer. Pinned and hidden layers let it
    /// through to the layer below or the image.
    func press(at point: CGPoint, scale: CGFloat) -> Bool {
        guard let part = part(at: point, scale: scale) else { return false }
        let id: UUID
        switch part {
        case .layer(let layer): id = layer
        case .corner(let layer, _): id = layer
        }
        guard let layer = stack.layers.first(where: { $0.id == id }) else { return false }
        if stack.selectedID != id { select(id) }
        drag = (part, point, layer)
        return true
    }

    var isDragging: Bool { drag != nil }

    func drag(to point: CGPoint) {
        guard let drag else { return }
        let state = zoomPan.state
        let layer: ReferenceLayer
        switch drag.part {
        case .layer:
            let delta = CGPoint(
                x: (point.x - drag.startPoint.x) / state.zoom, y: (point.y - drag.startPoint.y) / state.zoom)
            layer = ReferenceStack.moved(drag.startLayer, from: drag.startLayer.origin, by: delta)
        case .corner(_, let corner):
            layer = ReferenceStack.scaled(
                drag.startLayer, corner: corner, to: state.sourcePoint(forViewportPoint: point))
        }
        update(layer.id) { $0 = layer }
    }

    func endDrag() {
        drag = nil
    }

    static func cursor(for part: Part?, dragging: Bool) -> NSCursor? {
        switch part {
        case .layer?: dragging ? .closedHand : .openHand
        case .corner(_, let corner)?:
            OverlayStyle.cursor(
                for: .resize(
                    corner == .topLeft
                        ? .topLeft
                        : corner == .topRight ? .topRight : corner == .bottomLeft ? .bottomLeft : .bottomRight))
        case nil: nil
        }
    }
}
