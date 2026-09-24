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

    /// The panel's content scale, 1 at 250 pt wide (docs/product.md, References).
    var scale: CGFloat = 1

    var stack: ReferenceStack { project.project.references }

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let project: ProjectStore
    @ObservationIgnored private let zoomPan: ZoomPanController
    @ObservationIgnored private var images: [UUID: CGImage] = [:]
    @ObservationIgnored private var drag: (part: Part, startPoint: CGPoint, startLayer: ReferenceLayer)?
    /// Bumped on every change, so SwiftUI redraws what reads `stack` through the project.
    private var revision = 0

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

    func image(for layer: ReferenceLayer) -> CGImage? {
        if let image = images[layer.id] { return image }
        let url = project.imageURL(for: layer.fileName)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        images[layer.id] = image
        return image
    }

    /// Reads `revision` so SwiftUI views that call this update on every change.
    var layers: [ReferenceLayer] {
        _ = revision
        return stack.layers
    }

    var selectedID: UUID? {
        _ = revision
        return stack.selectedID
    }

    func update(_ change: (inout ReferenceStack) -> Void) {
        project.update { change(&$0.references) }
        revision += 1
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

    /// Asks for images and adds each as a layer on top, as many as the limit allows.
    func addFromFiles(in window: NSWindow?) {
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
