/// The Viewer's Metal shaders, compiled at launch with `MTLDevice.makeLibrary(source:options:)`.
///
/// Kept as source rather than a `.metal` file so building the app doesn't need Xcode's separately
/// downloaded Metal toolchain.
enum ViewerShaders {
    static let source = """
        #include <metal_stdlib>
        using namespace metal;

        // One textured quad: the captured frame, placed by the CPU in normalized device coordinates.

        struct QuadUniforms {
            // Left, top, right, bottom in NDC (top > bottom).
            float4 rect;
        };

        struct QuadVertex {
            float4 position [[position]];
            float2 uv;
        };

        vertex QuadVertex quadVertex(uint vertexID [[vertex_id]], constant QuadUniforms &uniforms [[buffer(0)]]) {
            // Triangle strip: top-left, top-right, bottom-left, bottom-right.
            const float2 corners[4] = { float2(0, 0), float2(1, 0), float2(0, 1), float2(1, 1) };
            float2 corner = corners[vertexID];
            QuadVertex out;
            out.position = float4(mix(uniforms.rect.x, uniforms.rect.z, corner.x),
                                  mix(uniforms.rect.y, uniforms.rect.w, corner.y), 0, 1);
            out.uv = corner;
            return out;
        }

        fragment float4 quadFragment(QuadVertex in [[stage_in]], texture2d<float> frame [[texture(0)]]) {
            // Magnification is always nearest-neighbor, so source pixels stay crisp squares; zooming
            // out below 1:1 is filtered so it doesn't shimmer (docs/design.md §2.3).
            constexpr sampler pixels(mag_filter::nearest, min_filter::linear, address::clamp_to_edge);
            return frame.sample(pixels, in.uv);
        }
        """
}
