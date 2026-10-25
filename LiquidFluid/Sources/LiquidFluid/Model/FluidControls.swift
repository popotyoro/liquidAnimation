import Observation

/// UIが発行する操作と、描画側が低頻度で返す計測値を保持する。
/// パッケージ既定のMainActor隔離を利用し、毎フレームの水面配列はここへ載せない。
@Observable
public final class FluidControls {
    enum Request {
        case show
        case pour(from: Double?)
    }

    public nonisolated enum Feedback: Equatable, Sendable {
        case started, firstContact, completed
    }

    public var configuration = FluidConfiguration()
    @ObservationIgnored private var pendingRequest: Request?
    /// 最後に要求された合計割合。設定画面のfillは、次に空から注ぐときの指定値。
    public private(set) var targetFraction = 0.0
    public private(set) var feedback: Feedback?
    public var isPaused = false
    public var isHapticFeedbackEnabled = true
    public internal(set) var status = "注水して動きを確認"
    public var error: String?
    public internal(set) var insertedFraction = 0.0
    public internal(set) var framesPerSecond = 0.0
    public internal(set) var gpuMilliseconds = 0.0
    public internal(set) var simulationMilliseconds = 0.0

    public init(initialFraction: Double = 0) {
        if initialFraction != 0 { show(fraction: initialFraction) }
    }

    /// 空の状態から、現在の設定で注水し直す要求を発行する。
    public func pour() {
        isPaused = false
        targetFraction = configuration.sanitized.fill
        pendingRequest = .pour(from: 0)
        feedback = nil
    }

    /// 現在量を残し、指定した合計割合まで追加する。減量はshow(fraction:)で反映する。
    public func pour(to fraction: Double) {
        guard fraction.isFinite else { return }
        let target = min(1, max(0, fraction))
        guard target > targetFraction else { return }
        let initial: Double?
        switch pendingRequest {
        case .show: initial = targetFraction
        case .pour(let from): initial = from
        case nil: initial = nil
        }
        targetFraction = target
        isPaused = false
        pendingRequest = .pour(from: initial)
        feedback = nil
    }

    /// 記録済みの割合を注水せずに表示し、進行中の注水要求を取り消す。
    public func show(fraction: Double) {
        let fraction = fraction.isFinite ? min(1, max(0, fraction)) : 0
        targetFraction = fraction
        insertedFraction = fraction
        isPaused = false
        pendingRequest = .show
        feedback = nil
        status = fraction > 0 ? "記録済みの量を表示" : "注水して動きを確認"
    }

    /// 水面・水流・飛沫を消す要求を発行し、表示上の投入量も戻す。
    public func reset() {
        show(fraction: 0)
    }

    /// 描画側が一度だけ受け取り、未処理の要求を消費する。
    func takeRequest() -> Request? {
        defer { pendingRequest = nil }
        return pendingRequest
    }

    func reportFeedback(_ feedback: Feedback) { self.feedback = feedback }
}
