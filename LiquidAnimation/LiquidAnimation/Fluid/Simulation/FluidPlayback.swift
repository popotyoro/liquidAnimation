import QuartzCore

/// 操作要求の消費順序と再生時刻を管理する。MetalやViewを持たず、停止中も操作を受け取る。
struct FluidPlayback {
    private var previousTime: CFTimeInterval?

    func hasPendingPour(_ model: WaterModel, controls: FluidControls) -> Bool {
        controls.targetFraction * model.capacity > model.configuration.fill * model.capacity + WaterModel.minimumPourArea
    }

    mutating func advance(_ model: WaterModel, controls: FluidControls, now: CFTimeInterval) {
        consumeRequests(model, controls: controls)
        if hasPendingPour(model, controls: controls), !controls.isPaused, !model.isPouring, model.jetFraction == 0 {
            if !model.hasWater { model.reset(configuration: controls.configuration, start: false) }
            if model.pour(to: controls.targetFraction) { controls.reportFeedback(.started) }
        }
        let hadContact = model.hasMadeFirstContact
        let wasPouring = model.isPouring
        // 復帰や処理落ち後も大量の追いつき計算をしない。Floatへの丸めも従来どおり。
        let dt = Float(min(max(now - (previousTime ?? (now - 1 / 60)), 0), 1 / 60))
        previousTime = now
        if !controls.isPaused && (model.hasWater || model.isPouring) {
            model.advance(by: Double(dt))
        }
        if !hadContact && model.hasMadeFirstContact { controls.reportFeedback(.firstContact) }
        if wasPouring && !model.isPouring && !hasPendingPour(model, controls: controls) {
            controls.reportFeedback(.completed)
        }
    }

    mutating func discardElapsedTime() { previousTime = nil }

    /// リサイズで空に戻した場合、直前の操作要求を新しい容器へ持ち越さない。
    func acknowledgeRequests(from controls: FluidControls) {
        _ = controls.takeRequest()
    }

    private mutating func consumeRequests(_ model: WaterModel, controls: FluidControls) {
        switch controls.takeRequest() {
        case .show:
            model.reset(configuration: controls.configuration, start: false, initialFraction: controls.targetFraction)
        case .pour(let initial):
            if let initial {
                model.reset(configuration: controls.configuration, start: false, initialFraction: initial)
            }
        case nil:
            break
        }
    }
}
