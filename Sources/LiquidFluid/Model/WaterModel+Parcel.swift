extension WaterModel {
    /// 水流を時間区間ごとの面積で記録する。丸い粒として描くためのデータではない。
    struct Parcel {
        var time: Double
        var area: Double
    }
}
