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

        struct FragmentUniforms {
            // The captured image in source pixels.
            float2 imageSize;
            // Drawable pixels per source pixel.
            float zoom;
            // The pixel grid: 0 none, 1 auto lines, 2 dark lines, 3 light lines.
            float grid;
        };

        fragment float4 quadFragment(QuadVertex in [[stage_in]], texture2d<float> frame [[texture(0)]],
                                     constant FragmentUniforms &uniforms [[buffer(0)]]) {
            // Magnification is always nearest-neighbor, so source pixels stay crisp squares; zooming
            // out below 1:1 is linearly filtered (docs/design.md §2.3).
            constexpr sampler pixels(mag_filter::nearest, min_filter::linear, address::clamp_to_edge);
            float4 color = frame.sample(pixels, in.uv);
            if (uniforms.grid > 0.5) {
                // How far into its source pixel this drawable pixel is, in drawable pixels. The first
                // drawable pixel of every source pixel (left and top edge) becomes the grid line, so
                // lines sit exactly on pixel boundaries and are one drawable pixel wide.
                float2 into = fract(in.uv * uniforms.imageSize) * uniforms.zoom;
                if (into.x < 1.0 || into.y < 1.0) {
                    float luma = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
                    float3 line = uniforms.grid > 2.5 ? float3(1.0)
                        : uniforms.grid > 1.5 ? float3(0.0)
                        : (luma > 0.5 ? float3(0.0) : float3(1.0));
                    color.rgb = mix(color.rgb, line, 0.22);
                }
            }
            return color;
        }

        struct ReferenceUniforms {
            // Where the layer's corners fall in the frame texture: offset (xy) and size (zw) in the
            // frame's UV, for the difference blend.
            float4 frameUV;
            float opacity;
            // 1: the absolute difference from the live frame; 0: the image as it is.
            float difference;
            float2 unused;
        };

        // A reference layer over the frame. Its texture is premultiplied, in the Viewer's colour
        // space; blending is premultiplied source-over.
        fragment float4 referenceFragment(QuadVertex in [[stage_in]], texture2d<float> reference [[texture(0)]],
                                          texture2d<float> frame [[texture(1)]],
                                          constant ReferenceUniforms &uniforms [[buffer(0)]]) {
            constexpr sampler pixels(mag_filter::nearest, min_filter::linear, address::clamp_to_edge);
            float4 color = reference.sample(pixels, in.uv);
            if (uniforms.difference > 0.5) {
                float2 uv = uniforms.frameUV.xy + in.uv * uniforms.frameUV.zw;
                bool inside = all(uv >= 0.0) && all(uv <= 1.0);
                float3 live = inside ? frame.sample(pixels, uv).rgb : float3(0.0);
                float3 straight = color.a > 0.0 ? color.rgb / color.a : float3(0.0);
                color = float4(abs(straight - live) * color.a, color.a);
            }
            return color * uniforms.opacity;
        }

        struct CheckerUniforms {
            float4 first;
            float4 second;
            // x: the side of a square in drawable pixels.
            float4 size;
        };

        // The checkerboard background, drawn over the whole viewport before the frame.
        fragment float4 checkerFragment(QuadVertex in [[stage_in]], constant CheckerUniforms &uniforms [[buffer(0)]]) {
            float2 square = floor(in.position.xy / uniforms.size.x);
            return fmod(square.x + square.y, 2.0) < 0.5 ? uniforms.first : uniforms.second;
        }
        """
}
