// 注水の設定値と、SwiftUI・描画ループ間で共有する操作状態を定義する。
import Foundation
import Observation

/// 1回の注水に使う値。シミュレーション開始時にコピーし、不透明度だけ描画時に即時反映する。
nonisolated struct FluidConfiguration: Equatable, Sendable {
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

/// UIが発行する操作と、描画側が低頻度で返す計測値を保持する。
/// アプリ既定のMainActor隔離を利用し、毎フレームの水面配列はここへ載せない。
@Observable
final class FluidControls {
    var configuration = FluidConfiguration()
    // IDの変化を描画ループが検出する。同じ操作の繰り返しも通知できる。
    private(set) var restartID = 0
    private(set) var resetID = 0
    var isPaused = false
    var status = "注水して動きを確認"
    var error: String?
    var insertedFraction = 0.0
    var framesPerSecond = 0.0
    var gpuMilliseconds = 0.0
    var simulationMilliseconds = 0.0

    /// 空の状態から、現在の設定で注水し直す要求を発行する。
    func pour() {
        isPaused = false
        restartID += 1
    }

    /// 水面・水流・飛沫を消す要求を発行し、表示上の投入量も戻す。
    func reset() {
        isPaused = false
        resetID += 1
        insertedFraction = 0
        status = "注水して動きを確認"
    }
}
