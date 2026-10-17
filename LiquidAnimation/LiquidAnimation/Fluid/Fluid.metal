#include <metal_stdlib>
using namespace metal;

struct WaterVertex { float2 position; float2 texture; };
struct WaterUniforms { float4 viewport; };
struct WaterRaster { float4 position [[position]]; float2 uv; };

vertex WaterRaster waterVertex(uint id [[vertex_id]]) {
    float2 points[3] = {float2(-1,-1), float2(3,-1), float2(-1,3)};
    WaterRaster result;
    result.position = float4(points[id], 0, 1);
    result.uv = points[id] * 0.5f + 0.5f;
    return result;
}

fragment half4 waterFragment(WaterRaster in [[stage_in]],
                             constant WaterUniforms &s [[buffer(0)]],
                             device const float *heights [[buffer(1)]]) {
    uint count = uint(s.viewport.w);
    float coordinate = clamp(in.uv.x * float(count) - 0.5f, 0.0f, float(count - 1));
    uint left = uint(coordinate), right = min(left + 1, count - 1);
    float surface = mix(heights[left], heights[right], fract(coordinate));
    if (surface <= 1e-7f || s.viewport.z <= 0) return half4(0);
    float distance = (surface - in.uv.y) * s.viewport.y;
    float coverage = smoothstep(-0.7f, 0.7f, distance);
    if (coverage <= 0) return half4(0);
    float depth = clamp(surface - in.uv.y, 0.0f, 1.0f);
    float3 color = mix(float3(0.08f,0.65f,0.85f), float3(0.015f,0.32f,0.63f), min(1.0f, depth * 1.5f));
    // One highlight follows the continuous waterline, rather than shading every marker.
    float rim = exp(-max(0.0f, distance) * 0.65f);
    color += rim * float3(0.22f,0.23f,0.22f);
    float alpha = coverage * s.viewport.z;
    return half4(half3(color * alpha), half(alpha));
}

vertex WaterRaster streamVertex(uint id [[vertex_id]], device const WaterVertex *vertices [[buffer(0)]]) {
    WaterRaster result;
    result.position = float4(vertices[id].position * 2 - 1, 0, 1);
    result.uv = vertices[id].texture;
    return result;
}

fragment half4 streamFragment(WaterRaster in [[stage_in]], constant WaterUniforms &s [[buffer(0)]]) {
    float coverage = 1 - smoothstep(0.82f, 1.0f, abs(in.uv.x));
    float sheen = exp(-pow((in.uv.x + 0.45f) * 6, 2.0f));
    float3 color = float3(0.06f,0.61f,0.84f) + sheen * 0.16f;
    float alpha = coverage * s.viewport.z;
    return half4(half3(color * alpha), half(alpha));
}
