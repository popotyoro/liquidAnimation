/// Fluid.metalの同名構造体とフィールド順序・型・サイズを一致させる。
nonisolated struct WaterVertex: Sendable {
    var position: SIMD2<Float> // 描画領域で正規化した位置。左下が(0, 0)。
    var texture: SIMD2<Float> // 水流では横断方向、飛沫では楕円の局所座標として使う。
}
