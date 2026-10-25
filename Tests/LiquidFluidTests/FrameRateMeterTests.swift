import Testing
@testable import LiquidFluid

/// 実時間を待たず、各ケースが所有する値型の計測器へ時刻を入力する。
/// 後始末はローカル値の破棄で完了する。
struct FrameRateMeterTests {
    @Test("集計開始から0.5秒未満ではFPSを通知しない", arguments: [10.1, 10.49])
    func framesWaitForReportingInterval(time: Double) {
        // 準備
        var meter = FrameRateMeter(startedAt: 10)

        // 実行
        let rate = meter.recordFrame(at: time)

        // 検証
        #expect(rate == nil)
    }

    @Test("0.5秒に達すると完了フレーム数を実経過時間で割ったFPSを返す")
    func completedFramesUseElapsedTime() {
        // 準備
        var meter = FrameRateMeter(startedAt: 10)
        _ = meter.recordFrame(at: 10.1)
        _ = meter.recordFrame(at: 10.2)

        // 実行
        let rate = meter.recordFrame(at: 10.5)

        // 検証
        #expect(rate == 6)
    }

    @Test("通知から0.5秒未満では次のFPSを通知しない")
    func reportingRestartsTheInterval() {
        // 準備
        var meter = FrameRateMeter(startedAt: 10)
        _ = meter.recordFrame(at: 10.5)

        // 実行
        let rate = meter.recordFrame(at: 10.75)

        // 検証
        #expect(rate == nil)
    }

    @Test("通知後のFPSには前の集計期間のフレームを含めない")
    func reportingRestartsTheFrameCount() {
        // 準備
        var meter = FrameRateMeter(startedAt: 10)
        _ = meter.recordFrame(at: 10.5)
        _ = meter.recordFrame(at: 10.75)

        // 実行
        let rate = meter.recordFrame(at: 11)

        // 検証
        #expect(rate == 4)
    }

    @Test("通知間隔を過ぎても固定の0.5秒ではなく実経過時間で集計する")
    func delayedFramesUseActualInterval() {
        // 準備
        var meter = FrameRateMeter(startedAt: 10)
        _ = meter.recordFrame(at: 10.25)

        // 実行
        let rate = meter.recordFrame(at: 12)

        // 検証
        #expect(rate == 1)
    }
}
