import Foundation
import Observation

struct FluidConfiguration: Equatable {
    var fill = 0.5
    var opacity = 0.45
    var sourcePosition = 0.25
    var angle = 30.0
    var flow = 0.08

    var sanitized: Self {
        var value = self
        value.fill = fill.isFinite ? min(max(fill, 0), 1) : 0.5
        value.opacity = opacity.isFinite ? min(max(opacity, 0), 1) : 0.45
        value.sourcePosition = sourcePosition.isFinite ? min(max(sourcePosition, 0.15), 0.85) : 0.25
        value.angle = angle.isFinite ? min(max(angle, -65), 65) : 30
        value.flow = flow.isFinite ? min(max(flow, 0.02), 0.16) : 0.08
        return value
    }
}

@Observable
@MainActor
final class FluidControls {
    var configuration = FluidConfiguration()
    private(set) var restartID = 0
    private(set) var resetID = 0
    var isPaused = false
    var status = "注水して動きを確認"
    var error: String?
    var insertedFraction = 0.0
    var framesPerSecond = 0.0
    var gpuMilliseconds = 0.0
    var simulationMilliseconds = 0.0

    func pour() {
        isPaused = false
        restartID += 1
    }

    func reset() {
        isPaused = false
        resetID += 1
        insertedFraction = 0
        status = "注水して動きを確認"
    }
}
