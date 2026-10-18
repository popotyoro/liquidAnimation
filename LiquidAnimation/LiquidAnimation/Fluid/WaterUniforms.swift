/// 各描画パスで共用する定数。Metal側とのメモリ配置を揃える。
nonisolated struct WaterUniforms: Sendable {
    var viewport: SIMD4<Float> // ピクセル幅・高さ、不透明度、水面の列数。
    var detail: SIMD4<Float> = .zero // 着水中心x、圧力の強さ、物理時刻、容器の縦横比。
}
