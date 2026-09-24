import CoreVideo
import MetalKit
import OSLog

/// Draws the latest captured frame into the Viewer's `MTKView` (docs/design.md §2.3).
///
/// The frame's IOSurface becomes a Metal texture through `CVMetalTextureCache` without a copy. The
/// quad is placed in whole drawable pixels from `ZoomPanController`, so at integer zoom every source
/// pixel covers exactly N×N drawable pixels.
@MainActor
final class ViewerRenderer: NSObject, MTKViewDelegate {
    var style = ViewerStyle()
    /// The visible reference layers, bottom first (docs/product.md, References).
    var references: () -> [(layer: ReferenceLayer, image: CGImage)] = { [] }
    /// Called when a reference texture made off the main thread is ready to draw.
    var onTextureReady: (() -> Void)?

    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let checkerPipeline: MTLRenderPipelineState
    private let referencePipeline: MTLRenderPipelineState
    private let device: MTLDevice
    /// Each layer's image as a texture in the Viewer's colour space, remade when either changes.
    private var referenceTextures: [UUID: (image: CGImage, space: CGColorSpace, texture: MTLTexture)] = [:]
    /// Layers whose texture is being made.
    private var pendingTextures: Set<UUID> = []
    private let textureCache: CVMetalTextureCache
    private let frameStore: FrameStore
    private let zoomPan: ZoomPanController
    private let log = Logger(category: "viewer")

    init?(view: MTKView, frameStore: FrameStore, zoomPan: ZoomPanController) {
        guard let device = view.device,
            let queue = device.makeCommandQueue()
        else { return nil }
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: ViewerShaders.source, options: nil)
        } catch {
            Logger(category: "viewer")
                .error("Shader compilation failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "quadVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "quadFragment")
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        let checkerDescriptor = descriptor.copy() as! MTLRenderPipelineDescriptor
        checkerDescriptor.fragmentFunction = library.makeFunction(name: "checkerFragment")
        let referenceDescriptor = descriptor.copy() as! MTLRenderPipelineDescriptor
        referenceDescriptor.fragmentFunction = library.makeFunction(name: "referenceFragment")
        let blending = referenceDescriptor.colorAttachments[0]!
        blending.isBlendingEnabled = true
        blending.sourceRGBBlendFactor = .one
        blending.sourceAlphaBlendFactor = .one
        blending.destinationRGBBlendFactor = .oneMinusSourceAlpha
        blending.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        var cache: CVMetalTextureCache?
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor),
            let checkerPipeline = try? device.makeRenderPipelineState(descriptor: checkerDescriptor),
            let referencePipeline = try? device.makeRenderPipelineState(descriptor: referenceDescriptor),
            CVMetalTextureCacheCreate(nil, nil, device, nil, &cache) == kCVReturnSuccess,
            let cache
        else { return nil }

        self.queue = queue
        self.pipeline = pipeline
        self.checkerPipeline = checkerPipeline
        self.referencePipeline = referencePipeline
        self.device = device
        self.textureCache = cache
        self.frameStore = frameStore
        self.zoomPan = zoomPan
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        zoomPan.setViewport(size)
    }

    func draw(in view: MTKView) {
        #if DEBUG
            frameStore.count { $0.drawCalls += 1 }
        #endif
        guard let pass = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable,
            let commands = queue.makeCommandBuffer(),
            let encoder = commands.makeRenderCommandEncoder(descriptor: pass)
        else { return }

        if style.background == .checkerboard {
            drawCheckerboard(encoder, view: view)
        }
        var texture: CVMetalTexture?
        var frameTexture: MTLTexture?
        let frame = frameStore.latestFrame
        #if DEBUG
            frameStore.count { $0.draws += 1 }
        #endif
        if let frame, let quad = quadRect(for: frame, drawableSize: view.drawableSize) {
            texture = makeTexture(frame.pixelBuffer)
            if let texture, let metalTexture = CVMetalTextureGetTexture(texture) {
                frameTexture = metalTexture
                var uniforms = quad
                let zoom = zoomPan.state.zoom
                var fragment = SIMD4<Float>(
                    Float(frame.pixelSize.width), Float(frame.pixelSize.height), Float(zoom), gridMode(zoom: zoom))
                encoder.setRenderPipelineState(pipeline)
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
                encoder.setFragmentBytes(&fragment, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
                encoder.setFragmentTexture(metalTexture, index: 0)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            }
        }
        drawReferences(encoder, view: view, frame: frame, frameTexture: frameTexture)
        encoder.endEncoding()
        commands.present(drawable)
        // The CVMetalTexture must outlive the GPU work that samples it; only held, never used, on the
        // completion handler's thread.
        let retained = UncheckedSendable(value: texture)
        commands.addCompletedHandler { _ in withExtendedLifetime(retained) {} }
        commands.commit()
        // The cache holds textures for buffers that are gone; the header asks for periodic flushes.
        CVMetalTextureCacheFlush(textureCache, 0)
    }

    private func drawReferences(
        _ encoder: MTLRenderCommandEncoder, view: MTKView, frame: CapturedFrame?, frameTexture: MTLTexture?
    ) {
        let layers = references()
        let space = view.colorspace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        referenceTextures = referenceTextures.filter { entry in layers.contains { $0.layer.id == entry.key } }
        guard !layers.isEmpty else { return }
        let state = zoomPan.state
        let size = view.drawableSize
        guard size.width > 0, size.height > 0 else { return }
        encoder.setRenderPipelineState(referencePipeline)
        for (layer, image) in layers {
            guard let texture = referenceTexture(layer.id, image: image, space: space) else { continue }
            let rect = state.imageRect(origin: layer.origin, size: layer.frame.size)
            var quad = SIMD4<Float>(
                Float(rect.minX / size.width * 2 - 1), Float(1 - rect.minY / size.height * 2),
                Float(rect.maxX / size.width * 2 - 1), Float(1 - rect.maxY / size.height * 2))
            // The layer's corners in the frame's UV: the frame covers its pixel size from its origin.
            var frameUV = SIMD4<Float>(0, 0, 0, 0)
            let difference = layer.blend == .difference && frameTexture != nil
            if difference, let frame {
                let pixels = CGSize(width: frame.pixelSize.width, height: frame.pixelSize.height)
                let origin = frame.geometry.imageOrigin
                frameUV = SIMD4(
                    Float((layer.origin.x - origin.x) / pixels.width),
                    Float((layer.origin.y - origin.y) / pixels.height),
                    Float(layer.frame.width / pixels.width), Float(layer.frame.height / pixels.height))
            }
            var uniforms = (frameUV, SIMD4<Float>(Float(layer.opacity), difference ? 1 : 0, 0, 0))
            encoder.setVertexBytes(&quad, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SIMD4<Float>>.stride * 2, index: 0)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.setFragmentTexture(frameTexture ?? texture, index: 1)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
    }

    /// The layer's texture, or `nil` until it is first made. Drawing a large image into a bitmap
    /// takes a while, so a missing or outdated texture is made off the main thread; the outdated one
    /// (after a move to a display with another colour space) is drawn meanwhile.
    private func referenceTexture(_ id: UUID, image: CGImage, space: CGColorSpace) -> MTLTexture? {
        let cached = referenceTextures[id]
        if let cached, cached.image === image, cached.space == space {
            return cached.texture
        }
        if pendingTextures.insert(id).inserted {
            let input = UncheckedSendable(value: (image: image, space: space, device: device))
            Task {
                let texture = await Self.makeTexture(input)
                pendingTextures.remove(id)
                guard let texture else { return }
                referenceTextures[id] = (image, space, texture.value)
                onTextureReady?()
            }
        }
        return cached?.texture
    }

    /// The image drawn into `space`, premultiplied BGRA, so a pixel that matches the screen has the
    /// same values as the capture.
    @concurrent
    nonisolated private static func makeTexture(
        _ input: UncheckedSendable<(image: CGImage, space: CGColorSpace, device: MTLDevice)>
    ) async -> UncheckedSendable<MTLTexture>? {
        let (image, space, device) = input.value
        // An image beyond the GPU's texture limit is scaled down to fit; the quad keeps the layer's
        // size, so it only loses detail.
        let limit = 16384
        let shrink = min(1, CGFloat(limit) / CGFloat(max(image.width, image.height)))
        let width = max(1, Int((CGFloat(image.width) * shrink).rounded(.down)))
        let height = max(1, Int((CGFloat(image.height) * shrink).rounded(.down)))
        guard image.width > 0, image.height > 0,
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
            let data = context.data
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: data, bytesPerRow: width * 4)
        return UncheckedSendable(value: texture)
    }

    /// The shader's grid value: 0 none, 1 auto, 2 dark, 3 light lines.
    private func gridMode(zoom: CGFloat) -> Float {
        guard style.showsGrid, zoom >= style.gridMinimumZoom else { return 0 }
        switch style.gridLines {
        case .auto: return 1
        case .dark: return 2
        case .light: return 3
        }
    }

    private func drawCheckerboard(_ encoder: MTLRenderCommandEncoder, view: MTKView) {
        let scale = view.drawableScale
        func color(_ c: SIMD3<Double>) -> SIMD4<Float> { SIMD4(Float(c.x), Float(c.y), Float(c.z), 1) }
        var uniforms = [
            color(ViewerBackground.checkerboard.components), color(ViewerBackground.checkerDarkComponents),
            SIMD4<Float>(Float(ViewerBackground.checkerSquare * scale), 0, 0, 0),
        ]
        var viewport = SIMD4<Float>(-1, 1, 1, -1)
        encoder.setRenderPipelineState(checkerPipeline)
        encoder.setVertexBytes(&viewport, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SIMD4<Float>>.stride * uniforms.count, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    /// The frame's quad in NDC: left, top, right, bottom.
    private func quadRect(for frame: CapturedFrame, drawableSize: CGSize) -> SIMD4<Float>? {
        guard drawableSize.width > 0, drawableSize.height > 0 else { return nil }
        let size = frame.pixelSize
        let rect = zoomPan.state.imageRect(
            origin: frame.geometry.imageOrigin, size: CGSize(width: size.width, height: size.height))
        let left = rect.minX
        let top = rect.minY
        let right = rect.maxX
        let bottom = rect.maxY
        func ndcX(_ x: CGFloat) -> Float { Float(x / drawableSize.width * 2 - 1) }
        func ndcY(_ y: CGFloat) -> Float { Float(1 - y / drawableSize.height * 2) }
        return SIMD4(ndcX(left), ndcY(top), ndcX(right), ndcY(bottom))
    }

    private func makeTexture(_ pixelBuffer: CVPixelBuffer) -> CVMetalTexture? {
        var texture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil, textureCache, pixelBuffer, nil, .bgra8Unorm,
            CVPixelBufferGetWidth(pixelBuffer), CVPixelBufferGetHeight(pixelBuffer), 0, &texture
        )
        if status != kCVReturnSuccess {
            log.error("Texture from frame failed: \(status)")
        }
        return texture
    }
}

/// How the Viewer draws around and over the image: the toolbar's grid toggle and Settings › Viewer.
struct ViewerStyle: Equatable {
    var showsGrid = false
    var gridMinimumZoom: CGFloat = 8
    var gridLines = GridLines.auto
    var background = ViewerBackground.dark
}

extension ViewerBackground {
    /// The fill, or the checkerboard's light squares, in the source display's colour space (the
    /// Viewer's layer is tagged with it).
    var components: SIMD3<Double> {
        switch self {
        case .dark: SIMD3(0.11, 0.11, 0.12)
        case .light: SIMD3(0.92, 0.92, 0.93)
        case .checkerboard: SIMD3(1, 1, 1)
        }
    }

    static let checkerDarkComponents = SIMD3<Double>(0.8, 0.8, 0.8)
    /// The side of a checkerboard square, in points.
    static let checkerSquare: CGFloat = 8

    var clearColor: MTLClearColor {
        MTLClearColor(red: components.x, green: components.y, blue: components.z, alpha: 1)
    }
}
