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
    static let backgroundColor = MTLClearColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)

    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
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

        var cache: CVMetalTextureCache?
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor),
            CVMetalTextureCacheCreate(nil, nil, device, nil, &cache) == kCVReturnSuccess,
            let cache
        else { return nil }

        self.queue = queue
        self.pipeline = pipeline
        self.textureCache = cache
        self.frameStore = frameStore
        self.zoomPan = zoomPan
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        zoomPan.setViewport(size)
    }

    func draw(in view: MTKView) {
        frameStore.count { $0.drawCalls += 1 }
        guard let pass = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable,
            let commands = queue.makeCommandBuffer(),
            let encoder = commands.makeRenderCommandEncoder(descriptor: pass)
        else { return }

        var texture: CVMetalTexture?
        let frame = frameStore.latestFrame
        frameStore.count {
            $0.draws += 1
            if frame != nil { $0.drawsWithFrame += 1 }
        }
        if let frame, let quad = quadRect(for: frame, drawableSize: view.drawableSize) {
            texture = makeTexture(frame.pixelBuffer)
            if let texture, let metalTexture = CVMetalTextureGetTexture(texture) {
                var uniforms = quad
                encoder.setRenderPipelineState(pipeline)
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
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
    }

    /// The frame's quad in NDC: left, top, right, bottom.
    private func quadRect(for frame: CapturedFrame, drawableSize: CGSize) -> SIMD4<Float>? {
        guard drawableSize.width > 0, drawableSize.height > 0 else { return nil }
        let state = zoomPan.state
        let origin = state.viewportPoint(forSourcePoint: frame.geometry.imageOrigin)
        let size = frame.pixelSize
        let left = origin.x
        let top = origin.y
        let right = left + CGFloat(size.width) * state.zoom
        let bottom = top + CGFloat(size.height) * state.zoom
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

/// Keeps a frame's texture alive until the GPU is done with it. Only held, never used, on the
/// completion handler's thread.
private struct RetainedTexture: @unchecked Sendable {
    let texture: CVMetalTexture?
}
