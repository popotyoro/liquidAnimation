import Foundation

/// 増流・定常・減流からなる注水曲線。流量とその解析的な積分を同じ定義で扱う。
struct PourEmission {
    let targetArea: Double
    let nominalRate: Double

    // 少量指定では増減区間を短くし、定常区間を省く。
    var rampDuration: Double { min(0.25, targetArea / nominalRate) }
    var duration: Double { targetArea > 0 ? targetArea / nominalRate + rampDuration : 0 }

    func rate(at instant: Double) -> Double {
        guard rampDuration > 0, instant > 0, instant < duration else { return 0 }
        let u = min(1, instant / rampDuration, (duration - instant) / rampDuration)
        return nominalRate * u * u * (3 - 2 * u)
    }

    /// 流量を刻みごとに近似加算せず、積分値との差分で投入量を決める。
    func cumulativeArea(at instant: Double) -> Double {
        guard rampDuration > 0, instant > 0 else { return 0 }
        if instant >= duration { return targetArea }
        if instant < rampDuration {
            return nominalRate * rampDuration * rampIntegral(instant / rampDuration)
        }
        if instant > duration - rampDuration {
            return targetArea - nominalRate * rampDuration * rampIntegral((duration - instant) / rampDuration)
        }
        return nominalRate * (instant - rampDuration / 2)
    }

    private func rampIntegral(_ u: Double) -> Double { u * u * u * (1 - 0.5 * u) }
}
