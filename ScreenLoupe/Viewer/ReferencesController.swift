import AppKit
import Observation

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
    /// the main thread; the Viewer draws it and the panel shows it once it is there. Upright as its
    /// EXIF orientation says, and past `ImageBudget` only its top-left part is kept.
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
        ImageFileLoader.image(at: url).map { UncheckedSendable(value: $0) }
    }

    func update(_ change: (inout ReferenceStack) -> Void) {
        project.update { change(&$0.references) }
        onChange?()
    }

    func update(_ id: UUID, _ change: (inout ReferenceLayer) -> Void) {
        update { $0.update(id, change) }
    }

    /// The Capture Area's top-left corner moved by `shift` source pixels: the layers stay on their
    /// pixels (`ReferenceStack.followAreaOrigin`).
    func areaOriginMoved(by shift: CGPoint) {
        guard shift != .zero, !stack.layers.isEmpty else { return }
        update { $0.followAreaOrigin(shift: shift) }
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
        panel.allowedContentTypes = ImageFileLoader.openableTypes
        panel.allowsMultipleSelection = true
        panel.message = "Choose design images to lay over the capture."
        let handle: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let self else { return }
            add(panel.urls)
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: handle)
        } else {
            handle(panel.runModal())
        }
    }

    /// Copies each image into the project and adds it as a layer on top, in order, until the stack
    /// is full; the last one added is selected. Returns the files that couldn't be read.
    @discardableResult
    func add(_ urls: [URL]) -> [URL] {
        var failed: [URL] = []
        for url in urls where stack.canAdd {
            guard let layer = project.importImage(at: url) else {
                failed.append(url)
                continue
            }
            update { $0.add(layer) }
        }
        return failed
    }

    /// The panel's Paste button (docs/product.md, Dropping and pasting images).
    @ObservationIgnored var onPaste: (() -> Void)?

    /// Writes pasted image data into the project and adds it as a layer on top, selected, one image
    /// pixel per source pixel as a dropped file. `false` when the stack is full or the data isn't an
    /// image.
    func add(_ data: Data, type: String, name: String) -> Bool {
        guard stack.canAdd, let layer = project.importImage(data: data, type: type, name: name)
        else { return false }
        update { $0.add(layer) }
        return true
    }

    // MARK: The mouse in the Viewer

    /// The selected layer's corner handles, in drawable pixels.
    func handles(scale: CGFloat) -> [(corner: ReferenceCorner, rect: CGRect)] {
        guard isActive, takesMouse, let layer = stack.selected, layer.isMovable else { return [] }
        // Where they show: over the presented view during a zoom glide.
        let rect = zoomPan.presented.imageRect(origin: layer.origin, size: layer.frame.size)
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
        let source = zoomPan.presented.sourcePoint(forViewportPoint: point)
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
