import QuartzCore

/// 操作要求の消費順序と再生時刻を管理する。MetalやViewを持たず、停止中も操作を受け取る。
struct FluidPlayback {
    private var previousTime: CFTimeInterval?
    private var lastRestart = 0
    private var lastReset = 0

    mutating func advance(_ model: WaterModel, controls: FluidControls, now: CFTimeInterval) {
        consumeRequests(model, controls: controls)
        // 復帰や処理落ち後も大量の追いつき計算をしない。Floatへの丸めも従来どおり。
        let dt = Float(min(max(now - (previousTime ?? (now - 1 / 60)), 0), 1 / 60))
        previousTime = now
        if !controls.isPaused && (model.hasWater || model.isPouring) {
            model.advance(by: Double(dt))
        }
    }

    mutating func discardElapsedTime() { previousTime = nil }

    /// リサイズで空に戻した場合、直前の操作要求を新しい容器へ持ち越さない。
    mutating func acknowledgeRequests(from controls: FluidControls) {
        lastRestart = controls.restartID
        lastReset = controls.resetID
    }

    private mutating func consumeRequests(_ model: WaterModel, controls: FluidControls) {
        // リセットは、それ以前の再注水要求も処理済みにする。
        if controls.resetID != lastReset {
            model.reset(configuration: controls.configuration, start: false)
            acknowledgeRequests(from: controls)
        }
        if controls.restartID != lastRestart {
            model.reset(configuration: controls.configuration, start: true)
            lastRestart = controls.restartID
        }
    }
}
