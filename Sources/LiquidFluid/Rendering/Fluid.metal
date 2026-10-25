// CPUが作成した水面・水流・飛沫・装飾用の気泡を描く。物理計算や背景画像の読み取りは行わない。
#include <metal_stdlib>
using namespace metal;

// Swift側と同じ順序・型で定義する。positionは左下原点の正規化座標。
struct WaterVertex { float2 position; float2 texture; };
// viewport = ピクセル幅・高さ、不透明度、水面の列数。
// detail = 着水中心x、着水圧力の強さ、物理時刻、縦横比。
// foam.xyzは泡の厚さ・白濁度・平均液深。Swift側と同じ112バイトの配置。
struct WaterUniforms {
    float4 viewport; float4 detail;
    float4 shallowColor; float4 deepColor; float4 streamColor; float4 edgeColor;
    float4 foam;
};
struct WaterRaster { float4 position [[position]]; float2 uv; };

// 左右の持ち上がりの平均を引き、水位の偏りを抑える。高さは画面幅で正規化。
float meniscusHeight(float x) {
    return 0.0075f * (exp(-x / 0.035f) + exp(-(1 - x) / 0.035f) - 0.07f);
}

// 着水圧力が消えると細かい波も消える。物理時刻を使うため停止中は動かない。
float impactRippleHeight(float x, float time, float pressure) {
    return 0.0025f * clamp(pressure, 0.0f, 1.0f)
        * (0.65f * sin(x * 31.41593f - time * 8)
           + 0.35f * sin(x * 56.54867f + time * 11));
}

// 着水点の両側に薄い肩を作り、外へ進むほど広がって水面へ戻す。
// 2つのパルスを重ねた表示用近似。巻き返りや砕波の物理計算ではない。
float impactShoulderHeight(float x, float time, float center, float pressure) {
    float strength = clamp(pressure, 0.0f, 1.0f);
    if (strength <= 1e-5f) return 0;
    float distance = x - center;
    float height = 0;
    for (int i = 0; i < 2; ++i) {
        float age = fract(time * 2.1f + float(i) * 0.5f);
        float envelope = pow(sin(age * M_PI_F), 2.0f);
        float travel = 0.018f + 0.080f * age;
        float width = 0.010f + 0.020f * age;
        float left = exp(-0.5f * pow((distance + travel) / width, 2.0f));
        float right = exp(-0.5f * pow((distance - travel) / width, 2.0f));
        // 着水中心は変えず、水流の先端と物理水面の接続を保つ。
        float outsideJet = 1 - exp(-pow(distance / 0.012f, 2.0f));
        height += 0.035f * strength * envelope * (left + right) * outsideJet;
    }
    return height;
}

// 全パスでalpha乗算済みの色を返し、one / oneMinusSourceAlphaの合成と揃える。
half4 premultipliedColor(float3 color, float alpha) {
    return half4(half3(color * alpha), half(alpha));
}

// 不規則な間隔・幅の丸い盛り上がり。大小2段で泡の集合を表す。
float foamMounds(float coordinate) {
    float cell = floor(coordinate);
    float height = 0;
    for (int i = -1; i <= 1; ++i) {
        float index = cell + i;
        float random = fract(sin(index * 127.1f + 19.7f) * 43758.5453f);
        float center = index + 0.25f + random * 0.5f;
        float radius = 0.30f + random * 0.18f;
        float offset = (coordinate - center) / radius;
        height = max(height, (0.65f + 0.35f * random) * exp(-offset * offset * 2));
    }
    return height;
}

// 上限の液面より内側へ凹凸を作る。泡が薄くなると凹凸も消える。
float foamSurfaceInset(float x, float time, float thickness, float depth) {
    if (thickness <= 0) return 0;
    float drift = 0.002f * sin(time * 0.4f);
    float mounds = 0.90f * foamMounds((x + drift) * 5)
        + 0.10f * foamMounds((x - drift) * 31 + 3.1f);
    float amplitude = min(0.026f, min(thickness * 0.35f, depth * 0.35f));
    return amplitude * (1 - mounds);
}

// 表示用の水面。壁際のメニスカスと、着水中だけの細かい波を重ねる。
// 液量の計算には使わない。空・満水では変形を消し、画面外へ水を増やさない。
float calculatedSurfaceHeight(float x, constant WaterUniforms &s, device const float *heights) {
    uint count = uint(s.viewport.w);
    float coordinate = clamp(x * float(count) - 0.5f, 0.0f, float(count - 1));
    uint left = uint(coordinate), right = min(left + 1, count - 1);
    float surface = mix(heights[left], heights[right], fract(coordinate));
    float aspect = max(s.detail.w, 0.5f);
    float room = smoothstep(0.0f, 0.04f, min(surface, 1 - surface) * aspect);
    float meniscus = meniscusHeight(x);
    float ripples = impactRippleHeight(x, s.detail.z, s.detail.y);
    float shoulders = impactShoulderHeight(x, s.detail.z, s.detail.x, s.detail.y);
    float visible = clamp(surface + room * (meniscus + ripples + shoulders) / aspect, 0.0f, 1.0f);
    return max(0.0f, visible - foamSurfaceInset(x, s.detail.z, s.foam.x, visible * aspect) / aspect);
}

// 画面全体を覆う大きな三角形。水の有無はフラグメント側で判定する。
vertex WaterRaster waterVertex(uint id [[vertex_id]]) {
    float2 points[3] = {float2(-1,-1), float2(3,-1), float2(-1,3)};
    WaterRaster result;
    result.position = float4(points[id], 0, 1);
    result.uv = points[id] * 0.5f + 0.5f;
    return result;
}

float waterSurfaceSlope(float x, constant WaterUniforms &s, device const float *heights) {
    // 表示用の波にも光が追従するよう、左右の水面から傾きを求める。
    float sampleStep = 1.0f / s.viewport.w;
    float sampleLeft = max(0.0f, x - sampleStep);
    float sampleRight = min(1.0f, x + sampleStep);
    return (calculatedSurfaceHeight(sampleRight, s, heights) - calculatedSurfaceHeight(sampleLeft, s, heights))
        * s.detail.w / max(sampleRight - sampleLeft, sampleStep);
}

// 表示水面と同じ有限差分の傾きを、横一列につき一度だけ計算する。
// 物理格子の更新はCPUのまま。これは描画用の形状キャッシュ。
kernel void prepareWaterSurface(uint index [[thread_position_in_grid]],
                                constant WaterUniforms &s [[buffer(0)]],
                                device const float *heights [[buffer(1)]],
                                device float2 *samples [[buffer(2)]]) {
    uint count = uint(s.foam.w);
    if (index >= count) return;
    float x = (float(index) + 0.5f) / float(count);
    samples[index] = float2(calculatedSurfaceHeight(x, s, heights), waterSurfaceSlope(x, s, heights));
}

float2 sampledSurface(float x, constant WaterUniforms &s, device const float2 *samples) {
    uint count = uint(s.foam.w);
    float coordinate = clamp(x * float(count) - 0.5f, 0.0f, float(count - 1));
    uint left = uint(coordinate), right = min(left + 1, count - 1);
    return mix(samples[left], samples[right], fract(coordinate));
}

// パレットの浅部・深部を基準に、光路長によるRGBごとの指数減衰を近似する。
// 光路長は水深や丸い断面から推定した表示用の値。背景の透過光はサンプルしない。
float3 attenuatedWaterColor(float3 nearColor, float3 farColor, float opticalDepth) {
    float3 transmission = clamp(farColor / max(nearColor, float3(0.001f)), 0.015f, 1.0f);
    return nearColor * exp(log(transmission) * clamp(opticalDepth, 0.0f, 2.0f));
}

// 空気と水の境界を想定したSchlick近似。正面の反射率は約2%。
float waterFresnel(float viewCosine) {
    return 0.0204f + 0.9796f * pow(1 - clamp(viewCosine, 0.0f, 1.0f), 5.0f);
}

// 固定された広い光源と細い光源を映す。背景・環境テクスチャや時刻には依存しない。
float waterReflection(float3 normal) {
    float3 reflected = reflect(float3(0, 0, -1), normal);
    float softbox = exp(-pow((reflected.x + 0.35f) / 0.42f, 2.0f)
                        -pow((reflected.y - 0.60f) / 0.65f, 2.0f));
    float strip = exp(-pow((reflected.x + 0.27f) / 0.075f, 2.0f)
                      -pow((reflected.y - 0.45f) / 0.80f, 2.0f));
    return min(0.65f, waterFresnel(normal.z) * (0.20f + 0.80f * softbox)
               + 0.25f * strip * sqrt(max(0.0f, normal.z)));
}

// 水面直下の丸みと波の傾きから法線を推定し、反射を輪郭に追従させる。
float3 surfaceLighting(float3 color, float x, float depth, float slope) {
    float curvature = exp(-depth / 0.010f);
    float3 normal = normalize(float3(-slope * curvature, curvature,
                                    sqrt(max(0.03f, 1 - curvature * curvature))));
    float lightPatch = exp(-pow((x - 0.30f + depth * 0.6f) / 0.55f, 2.0f));
    float reflection = waterReflection(normal) * exp(-depth * 24)
        * (0.35f + 0.65f * lightPatch);
    return mix(color, float3(0.90f, 0.97f, 1.0f), reflection);
}

float3 impactPlumeColor(float x, float depth, constant WaterUniforms &s) {
    // 着水点の淡い巻き込み模様。背景の屈折は行わない。
    float plumeX = (x - s.detail.x) / (0.025f + depth * 0.35f);
    float plume = exp(-plumeX * plumeX - depth * 12) * s.detail.y;
    float eddies = 0.5f + 0.5f * sin(x * 95 + depth * 70 + sin(depth * 35 - s.detail.z * 6));
    return plume * (0.025f + eddies * 0.075f) * float3(0.7f, 0.95f, 1.0f);
}

// 水流と水滴の丸い断面では中央ほど光路が長く、薄い縁ほど淡く見せる。
float3 roundedWaterColor(float3 normal, constant WaterUniforms &s) {
    float3 nearColor = mix(float3(0.85f, 0.94f, 0.98f), s.streamColor.rgb, 0.42f);
    float3 farColor = mix(s.streamColor.rgb, s.edgeColor.rgb, 0.25f);
    float3 color = attenuatedWaterColor(nearColor, farColor, normal.z);
    return mix(color, float3(0.90f, 0.97f, 1.0f), waterReflection(normal));
}

// 列ごとの水位を補間し、水面より下だけを半透明に着色する。
fragment half4 waterFragment(WaterRaster in [[stage_in]],
                             constant WaterUniforms &s [[buffer(0)]],
                             device const float2 *surfaceSamples [[buffer(1)]]) {
    float2 sample = sampledSurface(in.uv.x, s, surfaceSamples);
    float surface = sample.x;
    if (surface <= 1e-7f || s.viewport.z <= 0) return half4(0);
    // 水面までの距離をピクセル単位にし、境界を約1ピクセル幅で滑らかにする。
    float distance = (surface - in.uv.y) * s.viewport.y;
    float coverage = smoothstep(-0.7f, 0.7f, distance);
    if (coverage <= 0) return half4(0);
    float depth = clamp(surface - in.uv.y, 0.0f, 1.0f);
    // 容器幅で正規化した深さを光路長の代わりにする。縦横比にも追従する。
    float opticalDepth = depth * max(s.detail.w, 0.5f);
    float3 nearColor = mix(float3(0.80f, 0.90f, 0.95f), s.shallowColor.rgb, 0.62f);
    float3 color = attenuatedWaterColor(nearColor, s.deepColor.rgb, opticalDepth * 1.4f);
    float slope = sample.y;
    color = surfaceLighting(color, in.uv.x, opticalDepth, slope);
    // 広い光の濃淡で単色の面を和らげる。細かな模様や常時動く疑似的な渦は加えない。
    color *= 0.94f + 0.09f * exp(-pow((in.uv.x - 0.3f + depth * 0.4f) / 0.5f, 2.0f));
    color += impactPlumeColor(in.uv.x, depth, s);
    float alpha = coverage * s.viewport.z;
    return premultipliedColor(color, alpha);
}

// セルごとの中心を散らし、整列しない細かな泡の模様を作る。
float2 foamCellOffset(float2 cell) {
    return fract(sin(float2(dot(cell, float2(127.1f, 311.7f)),
                             dot(cell, float2(269.5f, 183.3f)))) * 43758.5453f);
}

float foamCellDistance(float2 point) {
    float2 cell = floor(point);
    float nearest = 2.0f;
    for (int y = -1; y <= 1; ++y) {
        for (int x = -1; x <= 1; ++x) {
            float2 neighbor = cell + float2(x, y);
            float2 center = neighbor + 0.2f + 0.6f * foamCellOffset(neighbor);
            nearest = min(nearest, length(point - center));
        }
    }
    return nearest;
}

// 液面の内側を泡で白濁させ、排液につれて下から液体を見せる。
// 液面より上への膨張は描かない。
fragment half4 foamFragment(WaterRaster in [[stage_in]],
                            constant WaterUniforms &s [[buffer(0)]],
                            device const float2 *surfaceSamples [[buffer(1)]]) {
    float thickness = s.foam.x;
    if (thickness <= 0 || s.viewport.z <= 0) return half4(0);
    float surface = sampledSurface(in.uv.x, s, surfaceSamples).x;
    if (surface <= 1e-7f) return half4(0);
    float aspect = max(s.detail.w, 0.5f);
    float aboveSurface = (in.uv.y - surface) * aspect;
    // 上端とは別に、平均液深と排液量から液体との境界を求める。
    // 局所水面から一定の厚さを引くと、上下の凹凸が複写されてしまう。
    float phase = in.uv.x + 0.003f * sin(s.detail.z * 0.4f);
    float unevenness = 0.008f * sin(in.uv.x * 13 + s.detail.z * 0.12f);
    float top = 0;
    float interfaceHeight = max(0.0f, s.foam.z * aspect - thickness * (1 + unevenness));
    float bottom = interfaceHeight - surface * aspect;
    float pixel = 1 / s.viewport.x;
    float transition = max(pixel * 2, thickness * 0.16f);
    float insideWater = 1 - smoothstep(top - pixel, top + pixel, aboveSurface);
    float head = smoothstep(bottom - transition, bottom + transition, aboveSurface);
    // 白濁が底から抜ける。境界を広くぼかし、硬い白帯とは別の層にする。
    float cloudiness = clamp(s.foam.y * 1.15f, 0.0f, 1.0f);
    float clearHeight = s.foam.z * (1 - cloudiness);
    float mist = cloudiness * smoothstep(clearHeight - s.foam.z * 0.12f,
                                         clearHeight + s.foam.z * 0.16f, in.uv.y);
    float coverage = insideWater * max(head, mist * 0.88f);
    if (coverage <= 0) return half4(0);
    // 模様も容器基準にし、上端の起伏を内部へ繰り返さない。
    float cells = foamCellDistance(float2(phase, in.uv.y * aspect) * 125);
    float rims = smoothstep(0.27f, 0.54f, cells);
    // 液中の濁りは黄みを残し、上の泡ほど白くする。細胞模様は控えめにする。
    float3 cream = mix(float3(0.99f, 0.98f, 0.93f), float3(0.86f, 0.82f, 0.69f), rims * 0.10f);
    float3 color = mix(float3(0.99f, 0.90f, 0.65f), cream, head);
    float elevation = clamp((aboveSurface - bottom) / max(top - bottom, pixel), 0.0f, 1.0f);
    color *= mix(0.94f, 1.0f, elevation);
    float alpha = coverage * (1 - pow(1 - s.viewport.z, 2.8f));
    return premultipliedColor(color, alpha);
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
    float body = sqrt(max(0.0f, 1 - in.uv.x * in.uv.x));
    float3 color = roundedWaterColor(float3(in.uv.x, 0, body), s);
    float alpha = coverage * s.viewport.z;
    return premultipliedColor(color, alpha);
}

// CPUが速度方向へ伸ばした四角形を、局所座標の円で切り抜くと楕円になる。
fragment half4 splashFragment(WaterRaster in [[stage_in]], constant WaterUniforms &s [[buffer(0)]]) {
    float distance = length(in.uv);
    float coverage = 1 - smoothstep(0.78f, 1.0f, distance);
    float body = sqrt(max(0.0f, 1 - distance * distance));
    float3 normal = normalize(float3(in.uv.x, -in.uv.y, max(0.001f, body)));
    float3 color = roundedWaterColor(normal, s);
    float alpha = coverage * s.viewport.z;
    return premultipliedColor(color, alpha);
}

// 気泡用の頂点は、水面に対する位置も渡して輪郭を水中へクリップする。
struct BubbleVertex { float2 position; float2 texture; float4 appearance; };
struct BubbleRaster { float4 position [[position]]; float2 uv; float2 waterUV; float opacity; float carbonation; };
vertex BubbleRaster bubbleVertex(uint id [[vertex_id]], device const BubbleVertex *vertices [[buffer(0)]]) {
    BubbleRaster result;
    result.position = float4(vertices[id].position * 2 - 1, 0, 1);
    result.uv = vertices[id].texture;
    result.waterUV = vertices[id].position;
    result.opacity = vertices[id].appearance.x;
    result.carbonation = vertices[id].appearance.y;
    return result;
}

// 中心をほぼ透明にし、明暗のある縁と反射光で空気の気泡を表す。
fragment half4 bubbleFragment(BubbleRaster in [[stage_in]],
                              constant WaterUniforms &s [[buffer(0)]],
                              device const float2 *surfaceSamples [[buffer(1)]]) {
    float surface = sampledSurface(in.waterUV.x, s, surfaceSamples).x;
    if (in.waterUV.y >= surface || s.viewport.z <= 0) return half4(0);
    float radius = length(in.uv);
    float emphasis = clamp(in.carbonation, 0.0f, 1.0f);
    float edgeWidth = max(mix(0.10f, 0.16f, emphasis), fwidth(radius));
    float ring = exp(-pow((radius - 0.78f) / edgeWidth, 2.0f));
    float glint = exp(-dot(in.uv - float2(-0.3f, 0.4f), in.uv - float2(-0.3f, 0.4f)) * 28);
    float coverage = 1 - smoothstep(0.92f, 1.0f, radius);
    float3 color = mix(s.deepColor.rgb, float3(0.85f,0.98f,1.0f),
                       clamp(0.5f + in.uv.y * 0.5f + glint, 0.0f, 1.0f));
    // 炭酸の輪郭はやや強く出す。不透明度0では気泡も完全に消す。
    float fluidOpacity = mix(s.viewport.z, 1 - pow(1 - s.viewport.z, 1.8f), emphasis);
    float shapeOpacity = mix(ring * 0.65f + glint * 0.55f,
                             min(1.0f, ring * 0.95f + glint * 0.80f), emphasis);
    float alpha = coverage * shapeOpacity * in.opacity * fluidOpacity;
    return premultipliedColor(color, alpha);
}
