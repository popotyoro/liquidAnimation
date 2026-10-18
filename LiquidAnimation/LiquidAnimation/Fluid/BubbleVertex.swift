/// 気泡の局所座標と寿命による濃さ。Metal側と32バイトの配置を揃える。
nonisolated struct BubbleVertex: Sendable {
    var position: SIMD2<Float>
    var texture: SIMD2<Float>
    var appearance: SIMD4<Float>
}
