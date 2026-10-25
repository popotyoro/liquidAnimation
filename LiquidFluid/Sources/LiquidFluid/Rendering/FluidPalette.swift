/// 浅い部分・深い部分・水流中央・水流の縁のRGB。wは予約領域。
/// 色を物理モデルから分離し、全描画パスへ同じパレットを渡す。
nonisolated struct FluidPalette: Equatable, Sendable {
    let shallow: SIMD4<Float>
    let deep: SIMD4<Float>
    let stream: SIMD4<Float>
    let edge: SIMD4<Float>

    static let blue = Self(shallow: SIMD4(0.08, 0.65, 0.85, 0), deep: SIMD4(0.015, 0.32, 0.63, 0),
        stream: SIMD4(0.06, 0.61, 0.84, 0), edge: SIMD4(0.025, 0.39, 0.67, 0))
    static let amber = Self(shallow: SIMD4(1, 0.67, 0.12, 0), deep: SIMD4(0.50, 0.18, 0.015, 0),
        stream: SIMD4(0.95, 0.56, 0.08, 0), edge: SIMD4(0.65, 0.24, 0.02, 0))
    static let green = Self(shallow: SIMD4(0.16, 0.74, 0.48, 0), deep: SIMD4(0.015, 0.34, 0.22, 0),
        stream: SIMD4(0.12, 0.68, 0.42, 0), edge: SIMD4(0.035, 0.40, 0.26, 0))
    static let pink = Self(shallow: SIMD4(0.90, 0.38, 0.63, 0), deep: SIMD4(0.45, 0.08, 0.30, 0),
        stream: SIMD4(0.85, 0.32, 0.57, 0), edge: SIMD4(0.52, 0.12, 0.35, 0))
}
