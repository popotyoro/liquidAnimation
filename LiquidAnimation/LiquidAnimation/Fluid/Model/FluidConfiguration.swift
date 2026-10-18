import Foundation

/// 1回の注水に使う値。シミュレーション開始時にコピーし、色と不透明度は描画時に即時反映する。
nonisolated struct FluidConfiguration: Equatable, Sendable {
    var kind: FluidKind = .water
    var color: FluidColorChoice = .standard

    /// 容器容量に対する投入総量。水面だけでなく、落下中の水と飛沫も含む。
    var fill = 0.5
    /// 0で透明、1で不透明。背後の画面の描画内容には依存しない。
    var opacity = 0.45
    /// 上辺の注水位置。左端が0、右端が1。
    var sourcePosition = 0.25
    /// 鉛直下向きを0度とし、正の値で右へ傾ける。
    var angle = 30.0
    /// 毎秒投入する容量の割合の最大値。開始・終了時はこの値より少なくする。
    var flow = 0.08

    /// 外部からの設定でもNaN・無限大・範囲外の値を物理計算へ渡さない。
    var sanitized: Self {
        var value = self
        value.fill = finiteValue(fill, in: 0...1, fallback: 0.5)
        value.opacity = finiteValue(opacity, in: 0...1, fallback: 0.45)
        value.sourcePosition = finiteValue(sourcePosition, in: 0.15...0.85, fallback: 0.25)
        value.angle = finiteValue(angle, in: -65...65, fallback: 30)
        value.flow = finiteValue(flow, in: 0.02...0.16, fallback: 0.08)
        return value
    }

    private func finiteValue(_ value: Double, in range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
    }
}
