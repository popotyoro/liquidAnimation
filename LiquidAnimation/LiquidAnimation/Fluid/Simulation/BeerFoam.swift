import Foundation

/// 泡に保持される液量と白濁の指数応答。容器内の総液量・運動量は変更しない。
nonisolated struct BeerFoam: Sendable {
    private(set) var liquidArea = 0.0
    private(set) var cloudiness = 0.0

    /// 注ぎ始めの保持率を高くし、6秒の時定数で排液する。係数は描画用の近似。
    mutating func advance(by dt: Double, arrivingArea: Double, landedArea: Double, capacity: Double) {
        let landedFraction = landedArea / capacity
        let foamingFraction = 0.12 + 0.78 * exp(-landedFraction / 0.08)
        liquidArea = min(landedArea,
            liquidArea * exp(-dt / 6) + arrivingArea * foamingFraction)
        // 着水による白濁と、微細気泡が抜ける過程を時間刻みに依存しない指数応答で扱う。
        let clearing = cloudiness * exp(-dt / 2.4)
        let entrainment = 1 - exp(-arrivingArea / (capacity * 0.025))
        cloudiness = clearing + (1 - clearing) * entrainment
    }
}
