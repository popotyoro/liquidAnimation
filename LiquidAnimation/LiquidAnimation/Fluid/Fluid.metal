// CPUが作成した水面・水流・飛沫を描く。物理計算や背景画像の読み取りは行わない。
#include <metal_stdlib>
using namespace metal;

// Swift側と同じ順序・型で定義する。positionは左下原点の正規化座標。
struct WaterVertex { float2 position; float2 texture; };
// viewport = ピクセル幅・高さ、不透明度、水面の列数。
struct WaterUniforms { float4 viewport; };
struct WaterRaster { float4 position [[position]]; float2 uv; };

// 画面全体を覆う大きな三角形。水の有無はフラグメント側で判定する。
vertex WaterRaster waterVertex(uint id [[vertex_id]]) {
    float2 points[3] = {float2(-1,-1), float2(3,-1), float2(-1,3)};
    WaterRaster result;
    result.position = float4(points[id], 0, 1);
    result.uv = points[id] * 0.5f + 0.5f;
    return result;
}

// 列ごとの水位を補間し、水面より下だけを半透明に着色する。
fragment half4 waterFragment(WaterRaster in [[stage_in]],
                             constant WaterUniforms &s [[buffer(0)]],
                             device const float *heights [[buffer(1)]]) {
    uint count = uint(s.viewport.w);
    // 水深サンプルはセルの中心にあるため、半セル分ずらして補間する。
    float coordinate = clamp(in.uv.x * float(count) - 0.5f, 0.0f, float(count - 1));
    uint left = uint(coordinate), right = min(left + 1, count - 1);
    float surface = mix(heights[left], heights[right], fract(coordinate));
    if (surface <= 1e-7f || s.viewport.z <= 0) return half4(0);
    // 水面までの距離をピクセル単位にし、境界を約1ピクセル幅で滑らかにする。
    float distance = (surface - in.uv.y) * s.viewport.y;
    float coverage = smoothstep(-0.7f, 0.7f, distance);
    if (coverage <= 0) return half4(0);
    float depth = clamp(surface - in.uv.y, 0.0f, 1.0f);
    float3 color = mix(float3(0.08f,0.65f,0.85f), float3(0.015f,0.32f,0.63f), min(1.0f, depth * 1.5f));
    // 各粒の光沢ではなく、連続する水面に沿うハイライトを付ける。
    float rim = exp(-max(0.0f, distance) * 0.65f);
    color += rim * float3(0.22f,0.23f,0.22f);
    float alpha = coverage * s.viewport.z;
    // alpha乗算済みの色を返す。Swift側のブレンド設定と対にする。
    return half4(half3(color * alpha), half(alpha));
}

// 水流の帯と飛沫の四角形メッシュで共用する頂点処理。
vertex WaterRaster streamVertex(uint id [[vertex_id]], device const WaterVertex *vertices [[buffer(0)]]) {
    WaterRaster result;
    result.position = float4(vertices[id].position * 2 - 1, 0, 1);
    result.uv = vertices[id].texture;
    return result;
}

// uv.xは帯の横断方向（-1〜1）。端をぼかし、片側に細い光沢を置く。
fragment half4 streamFragment(WaterRaster in [[stage_in]], constant WaterUniforms &s [[buffer(0)]]) {
    float coverage = 1 - smoothstep(0.82f, 1.0f, abs(in.uv.x));
    float sheen = exp(-pow((in.uv.x + 0.45f) * 6, 2.0f));
    float3 color = float3(0.06f,0.61f,0.84f) + sheen * 0.16f;
    float alpha = coverage * s.viewport.z;
    // alpha乗算済みの色を返す。Swift側のブレンド設定と対にする。
    return half4(half3(color * alpha), half(alpha));
}

// CPUが速度方向へ伸ばした四角形を、局所座標の円で切り抜くと楕円になる。
fragment half4 splashFragment(WaterRaster in [[stage_in]], constant WaterUniforms &s [[buffer(0)]]) {
    float distance = length(in.uv);
    float coverage = 1 - smoothstep(0.78f, 1.0f, distance);
    float highlight = exp(-pow((in.uv.x + 0.35f) * 5, 2.0f));
    float3 color = float3(0.06f, 0.61f, 0.84f) + highlight * 0.12f;
    float alpha = coverage * s.viewport.z;
    // alpha乗算済みの色を返す。Swift側のブレンド設定と対にする。
    return half4(half3(color * alpha), half(alpha));
}
