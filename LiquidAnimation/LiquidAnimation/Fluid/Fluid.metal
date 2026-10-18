// CPUが作成した水面・水流・飛沫・装飾用の気泡を描く。物理計算や背景画像の読み取りは行わない。
#include <metal_stdlib>
using namespace metal;

// Swift側と同じ順序・型で定義する。positionは左下原点の正規化座標。
struct WaterVertex { float2 position; float2 texture; };
// viewport = ピクセル幅・高さ、不透明度、水面の列数。
// detail = 着水中心x、着水圧力の強さ、物理時刻、縦横比。
struct WaterUniforms { float4 viewport; float4 detail; };
struct WaterRaster { float4 position [[position]]; float2 uv; };

// 表示用の水面。壁際のメニスカスと、着水中だけの細かい波を重ねる。
// 液量の計算には使わない。空・満水では変形を消し、画面外へ水を増やさない。
float visibleSurface(float x, constant WaterUniforms &s, device const float *heights) {
    uint count = uint(s.viewport.w);
    float coordinate = clamp(x * float(count) - 0.5f, 0.0f, float(count - 1));
    uint left = uint(coordinate), right = min(left + 1, count - 1);
    float surface = mix(heights[left], heights[right], fract(coordinate));
    float aspect = max(s.detail.w, 0.5f);
    float room = smoothstep(0.0f, 0.04f, min(surface, 1 - surface) * aspect);
    // 左右の持ち上がりに相当する平均を引き、全体の水位の偏りを抑える。
    float meniscus = 0.0075f * (exp(-x / 0.035f) + exp(-(1 - x) / 0.035f) - 0.07f);
    float ripples = 0.0025f * clamp(s.detail.y, 0.0f, 1.0f)
        * (0.65f * sin(x * 31.41593f - s.detail.z * 8)
           + 0.35f * sin(x * 56.54867f + s.detail.z * 11));
    return clamp(surface + room * (meniscus + ripples) / aspect, 0.0f, 1.0f);
}

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
    float surface = visibleSurface(in.uv.x, s, heights);
    if (surface <= 1e-7f || s.viewport.z <= 0) return half4(0);
    // 水面までの距離をピクセル単位にし、境界を約1ピクセル幅で滑らかにする。
    float distance = (surface - in.uv.y) * s.viewport.y;
    float coverage = smoothstep(-0.7f, 0.7f, distance);
    if (coverage <= 0) return half4(0);
    float depth = clamp(surface - in.uv.y, 0.0f, 1.0f);
    float3 color = mix(float3(0.08f,0.65f,0.85f), float3(0.015f,0.32f,0.63f), min(1.0f, depth * 1.5f));
    // 表示用の波にも光が追従するよう、左右の水面から傾きを求める。
    float sampleStep = 1.0f / float(count);
    float sampleLeft = max(0.0f, in.uv.x - sampleStep);
    float sampleRight = min(1.0f, in.uv.x + sampleStep);
    float slope = (visibleSurface(sampleRight, s, heights) - visibleSurface(sampleLeft, s, heights))
        * s.detail.w / max(sampleRight - sampleLeft, sampleStep);
    // 左上の広い光源を仮定した装飾的な反射。背景画像や環境マップは参照しない。
    // 反射は水面近くで減衰し、波が傾くと明暗が変わる。時刻だけでは動かさない。
    float facing = exp(-pow((slope + 0.12f) * 2.5f, 2.0f));
    float lightPatch = exp(-pow((in.uv.x - 0.28f + depth * 0.7f) / 0.28f, 2.0f));
    float reflection = facing * (0.08f + lightPatch * 0.22f) * exp(-depth * 32);
    color = mix(color, float3(0.86f,0.96f,1.0f), reflection);
    // 水面の縁に途切れる反射を置き、丸みを表す。輪郭に沿う暗い線は付けない。
    // 太さは画面幅基準。白い一本線にならないよう波の傾きで反射を弱める。
    float lipDepth = max(0.0f, distance) / max(1.0f, s.viewport.x * 0.018f);
    float crest = exp(-pow((lipDepth - 0.22f) * 4.5f, 2.0f));
    color = mix(color, float3(0.79f,0.94f,0.98f),
                crest * (0.10f + 0.32f * facing * lightPatch));
    // 広い光の濃淡で単色の面を和らげる。細かな模様や常時動く疑似的な渦は加えない。
    color *= 0.94f + 0.09f * exp(-pow((in.uv.x - 0.3f + depth * 0.4f) / 0.5f, 2.0f));
    // 着水点の淡い巻き込み模様。背景の屈折は行わない。
    float plumeX = (in.uv.x - s.detail.x) / (0.025f + depth * 0.35f);
    float plume = exp(-plumeX * plumeX - depth * 12) * s.detail.y;
    float eddies = 0.5f + 0.5f * sin(in.uv.x * 95 + depth * 70 + sin(depth * 35 - s.detail.z * 6));
    color += plume * (0.025f + eddies * 0.075f) * float3(0.7f, 0.95f, 1.0f);
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
    float sheen = exp(-pow((in.uv.x + 0.4f) * 5, 2.0f));
    float body = sqrt(max(0.0f, 1 - in.uv.x * in.uv.x));
    float3 color = mix(float3(0.025f,0.39f,0.67f), float3(0.06f,0.61f,0.84f), body);
    color = mix(color, float3(0.85f,0.96f,1.0f), sheen * 0.22f);
    float alpha = coverage * s.viewport.z;
    // alpha乗算済みの色を返す。Swift側のブレンド設定と対にする。
    return half4(half3(color * alpha), half(alpha));
}

// CPUが速度方向へ伸ばした四角形を、局所座標の円で切り抜くと楕円になる。
fragment half4 splashFragment(WaterRaster in [[stage_in]], constant WaterUniforms &s [[buffer(0)]]) {
    float distance = length(in.uv);
    float coverage = 1 - smoothstep(0.78f, 1.0f, distance);
    float2 lightOffset = in.uv - float2(-0.3f, 0.3f);
    float highlight = exp(-dot(lightOffset, lightOffset) * 14);
    float3 color = mix(float3(0.025f,0.39f,0.67f), float3(0.06f,0.61f,0.84f),
                       sqrt(max(0.0f, 1 - distance * distance)));
    color = mix(color, float3(0.85f,0.96f,1.0f), highlight * 0.48f);
    float alpha = coverage * s.viewport.z;
    // alpha乗算済みの色を返す。Swift側のブレンド設定と対にする。
    return half4(half3(color * alpha), half(alpha));
}

// 気泡用の頂点は、水面に対する位置も渡して輪郭を水中へクリップする。
struct BubbleVertex { float2 position; float2 texture; float4 appearance; };
struct BubbleRaster { float4 position [[position]]; float2 uv; float2 waterUV; float opacity; };
vertex BubbleRaster bubbleVertex(uint id [[vertex_id]], device const BubbleVertex *vertices [[buffer(0)]]) {
    BubbleRaster result;
    result.position = float4(vertices[id].position * 2 - 1, 0, 1);
    result.uv = vertices[id].texture;
    result.waterUV = vertices[id].position;
    result.opacity = vertices[id].appearance.x;
    return result;
}

// 中心をほぼ透明にし、明暗のある縁と反射光で空気の気泡を表す。
fragment half4 bubbleFragment(BubbleRaster in [[stage_in]],
                              constant WaterUniforms &s [[buffer(0)]],
                              device const float *heights [[buffer(1)]]) {
    float surface = visibleSurface(in.waterUV.x, s, heights);
    if (in.waterUV.y >= surface || s.viewport.z <= 0) return half4(0);
    float radius = length(in.uv);
    float edgeWidth = max(0.10f, fwidth(radius));
    float ring = exp(-pow((radius - 0.78f) / edgeWidth, 2.0f));
    float glint = exp(-dot(in.uv - float2(-0.3f, 0.4f), in.uv - float2(-0.3f, 0.4f)) * 28);
    float coverage = 1 - smoothstep(0.92f, 1.0f, radius);
    float3 color = mix(float3(0.05f,0.38f,0.57f), float3(0.85f,0.98f,1.0f),
                       clamp(0.5f + in.uv.y * 0.5f + glint, 0.0f, 1.0f));
    float alpha = coverage * (ring * 0.65f + glint * 0.55f) * in.opacity * s.viewport.z;
    return half4(half3(color * alpha), half(alpha));
}
