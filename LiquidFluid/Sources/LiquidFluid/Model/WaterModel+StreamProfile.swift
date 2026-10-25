extension WaterModel {
    /// 水流の描画にだけ使う輪郭。時刻は投入後の経過秒、半径はm。
    struct StreamProfile {
        let youngest: Double
        let oldest: Double
        let headRadius: Double
        let headDuration: Double
        let tailDuration: Double
    }
}
