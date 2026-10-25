/// 完了フレームを集計し、0.5秒ごとにFPSを返す。時計やUIの更新は呼び出し側が担当する。
nonisolated struct FrameRateMeter: Sendable {
    private var startedAt: Double
    private var frameCount = 0

    init(startedAt: Double) { self.startedAt = startedAt }

    mutating func recordFrame(at time: Double) -> Double? {
        frameCount += 1
        let interval = time - startedAt
        guard interval >= 0.5 else { return nil }
        let rate = Double(frameCount) / interval
        frameCount = 0
        startedAt = time
        return rate
    }
}
