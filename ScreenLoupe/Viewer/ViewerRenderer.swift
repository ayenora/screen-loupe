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

    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let checkerPipeline: MTLRenderPipelineState
    private let textureCache: CVMetalTextureCache
    private let frameStore: FrameStore
    private let zoomPan: ZoomPanController
    private let log = Logger(subsystem: "com.ayenora.screenloupe", category: "viewer")

    init?(view: MTKView, frameStore: FrameStore, zoomPan: ZoomPanController) {
        guard let device = view.device,
            let queue = device.makeCommandQueue()
        else { return nil }
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: ViewerShaders.source, options: nil)
        } catch {
            Logger(subsystem: "com.ayenora.screenloupe", category: "viewer")
                .error("Shader compilation failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "quadVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "quadFragment")
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        let checkerDescriptor = descriptor.copy() as! MTLRenderPipelineDescriptor
        checkerDescriptor.fragmentFunction = library.makeFunction(name: "checkerFragment")

        var cache: CVMetalTextureCache?
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor),
            let checkerPipeline = try? device.makeRenderPipelineState(descriptor: checkerDescriptor),
            CVMetalTextureCacheCreate(nil, nil, device, nil, &cache) == kCVReturnSuccess,
            let cache
        else { return nil }

        self.queue = queue
        self.pipeline = pipeline
        self.checkerPipeline = checkerPipeline
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
        let frame = frameStore.latestFrame
        #if DEBUG
            frameStore.count { $0.draws += 1 }
        #endif
        if let frame, let quad = quadRect(for: frame, drawableSize: view.drawableSize) {
            texture = makeTexture(frame.pixelBuffer)
            if let texture, let metalTexture = CVMetalTextureGetTexture(texture) {
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
        encoder.endEncoding()
        commands.present(drawable)
        // The CVMetalTexture must outlive the GPU work that samples it.
        let retained = RetainedTexture(texture: texture)
        commands.addCompletedHandler { _ in withExtendedLifetime(retained) {} }
        commands.commit()
        // The cache holds textures for buffers that are gone; the header asks for periodic flushes.
        CVMetalTextureCacheFlush(textureCache, 0)
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
        let scale = view.bounds.width > 0 ? view.drawableSize.width / view.bounds.width : 1
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

/// Keeps a frame's texture alive until the GPU is done with it. Only held, never used, on the
/// completion handler's thread.
private struct RetainedTexture: @unchecked Sendable {
    let texture: CVMetalTexture?
}
