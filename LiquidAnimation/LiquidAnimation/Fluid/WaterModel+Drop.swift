extension WaterModel {
    /// 独立した飛沫。水面へ戻ったら吸収し、再び跳ねさせない。
    struct Drop {
        var position: SIMD2<Double> // 単位はm、yは下向き。描画座標と上下が逆。
        var velocity: SIMD2<Double>
        var area: Double
        var detachedFromStream = false
    }
}
