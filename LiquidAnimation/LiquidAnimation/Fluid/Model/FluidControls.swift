import Observation

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
