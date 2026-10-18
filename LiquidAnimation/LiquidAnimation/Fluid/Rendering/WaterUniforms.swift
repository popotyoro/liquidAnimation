/// 各描画パスで共用する定数。Metal側と7個のfloat4・112バイトの配置を揃える。
nonisolated struct WaterUniforms: Sendable {
    var viewport: SIMD4<Float> // ピクセル幅・高さ、不透明度、水面の列数。
    var detail: SIMD4<Float> // 着水中心x、圧力の強さ、物理時刻、容器の縦横比。
    var shallowColor: SIMD4<Float>
    var deepColor: SIMD4<Float>
    var streamColor: SIMD4<Float>
    var edgeColor: SIMD4<Float>
    var foam: SIMD4<Float> = .zero // x: 幅基準の泡の厚さ、y: 白濁度、z: 高さ基準の平均液深。

    init(viewport: SIMD4<Float>, detail: SIMD4<Float> = .zero, palette: FluidPalette = .blue) {
        self.viewport = viewport
        self.detail = detail
        shallowColor = palette.shallow
        deepColor = palette.deep
        streamColor = palette.stream
        edgeColor = palette.edge
    }
}
