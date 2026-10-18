import Testing
@testable import LiquidAnimation

struct FrameRateMeterTests {
    @Test("0.5秒未満ではFPSを通知しない")
    func framesWaitForReportingInterval() {
        var meter = FrameRateMeter(startedAt: 10)
        #expect(meter.recordFrame(at: 10.1) == nil)
        #expect(meter.recordFrame(at: 10.49) == nil)
    }

    @Test("0.5秒に達すると完了フレーム数を実経過時間で割ったFPSを返す")
    func completedFramesUseElapsedTime() {
        var meter = FrameRateMeter(startedAt: 10)
        _ = meter.recordFrame(at: 10.1)
        _ = meter.recordFrame(at: 10.2)
        #expect(meter.recordFrame(at: 10.5) == 6)
    }

    @Test("通知後は前の集計を持ち越さず次の期間を数える")
    func reportingStartsANewInterval() {
        var meter = FrameRateMeter(startedAt: 10)
        #expect(meter.recordFrame(at: 10.5) == 2)
        #expect(meter.recordFrame(at: 10.75) == nil)
        #expect(meter.recordFrame(at: 11) == 4)
    }

    @Test("通知間隔を過ぎても固定の0.5秒ではなく実経過時間で集計する")
    func delayedFramesUseActualInterval() {
        var meter = FrameRateMeter(startedAt: 10)
        _ = meter.recordFrame(at: 10.25)
        #expect(meter.recordFrame(at: 12) == 1)
    }
}
