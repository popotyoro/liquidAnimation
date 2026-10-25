import Testing
@testable import LiquidAnimation

/// ケースごとに操作状態・モデル・再生時計を所有する。後始末はARCとスコープ終了で完結する。
@MainActor
struct WaterAdditionTests {
    @Test("許容誤差以下の追加量は注水待ちとして残らない")
    func negligibleAdditionDoesNotRemainPending() {
        // 準備
        let controls = FluidControls(initialFraction: 0.25)
        let water = WaterModel(aspectRatio: 2.16)
        var playback = FluidPlayback()
        playback.advance(water, controls: controls, now: 1)

        // 実行
        controls.pour(to: 0.25 + 1e-14)
        playback.advance(water, controls: controls, now: 2)

        // 検証
        #expect(abs(water.fraction - 0.25) < 1e-10)
        #expect(!water.isPouring)
        #expect(!playback.hasPendingPour(water, controls: controls))
        #expect(controls.feedback == nil)
    }

    @Test("静止中に設定の目標量を編集しても追加注水は始まらない")
    func editingTargetSettingDoesNotRequestAddition() {
        // 準備
        let controls = FluidControls(initialFraction: 0.25)
        let water = WaterModel(aspectRatio: 2.16)
        var playback = FluidPlayback()
        playback.advance(water, controls: controls, now: 1)

        // 実行
        controls.configuration.fill = 0.8
        for frame in 1...120 { playback.advance(water, controls: controls, now: 1 + Double(frame) / 60) }

        // 検証
        #expect(abs(water.fraction - 0.25) < 1e-10)
        #expect(controls.targetFraction == 0.25)
        #expect(!water.isPouring)
        #expect(!playback.hasPendingPour(water, controls: controls))
    }

    @Test("表示量を変更してすぐ追加すると変更後の水位から注ぐ")
    func showingThenPouringStartsAtUpdatedLevel() {
        // 準備
        let controls = FluidControls(initialFraction: 0.5)
        controls.configuration.flow = 0.16
        let water = WaterModel(aspectRatio: 2.16)
        var playback = FluidPlayback()
        playback.advance(water, controls: controls, now: 1)

        // 実行
        controls.show(fraction: 0.25)
        controls.pour(to: 0.4)
        playback.advance(water, controls: controls, now: 2)
        let initial = water.fraction
        for frame in 1...360 { playback.advance(water, controls: controls, now: 2 + Double(frame) / 60) }

        // 検証
        #expect(initial >= 0.25 && initial < 0.4)
        #expect(abs(water.landedFraction - 0.4) < 1e-8)
    }

    @Test("記録済みの量は注水せず平らな水面で表示される", arguments: [0.0, 0.25, 1.0])
    func initialAmountAppearsWithoutPouring(fraction: Double) {
        // 準備
        let controls = FluidControls(initialFraction: fraction)
        let water = WaterModel(aspectRatio: 2.16)
        var playback = FluidPlayback()

        // 実行
        playback.advance(water, controls: controls, now: 1)

        // 検証
        #expect(abs(water.fraction - fraction) < 1e-10)
        #expect(abs(water.landedFraction - fraction) < 1e-10)
        #expect(abs(water.meanDepth / water.height - fraction) < 1e-10)
        #expect(water.surfaceRange < 1e-10)
        #expect(!water.isPouring)
        #expect(water.streamVertices().isEmpty)
        #expect(controls.feedback == nil)
    }

    @Test("追加注水の開始で既存の水面・量・物理時刻は変わらない")
    func beginningAdditionPreservesExistingWater() throws {
        // 準備
        let water = WaterModel(aspectRatio: 2.16)
        water.reset(configuration: FluidConfiguration(), start: true)
        for _ in 0..<90 { water.advance(by: 1 / 60) }
        for _ in 0..<600 { water.advance(by: 1 / 60) }
        try #require(!water.isPouring && water.jetFraction == 0)
        let depths = water.depths
        let time = water.time
        let fraction = water.fraction
        let landed = water.landedArea

        // 実行
        let started = water.pour(to: 0.7)

        // 検証
        #expect(started)
        #expect(water.depths == depths)
        #expect(water.time == time)
        #expect(water.fraction == fraction)
        #expect(water.landedArea == landed)
        #expect(!water.hasMadeFirstContact)
    }

    @Test("25%から追加すると差分だけを注いで40%で止まる", arguments: FluidKind.allCases)
    func additionStopsAtTotalTarget(kind: FluidKind) {
        // 準備
        let controls = FluidControls(initialFraction: 0.25)
        controls.configuration.kind = kind
        controls.configuration.flow = 0.16
        let water = WaterModel(aspectRatio: 2.16)
        var playback = FluidPlayback()
        var fractions: [Double] = []
        var errors: [Double] = []
        controls.pour(to: 0.4)

        // 実行
        for frame in 1...480 {
            playback.advance(water, controls: controls, now: Double(frame) / 60)
            fractions.append(water.fraction)
            errors.append(abs(water.landedFraction + water.jetFraction + water.splashFraction - water.fraction))
        }

        // 検証
        #expect(fractions.allSatisfy { $0 >= 0.25 && $0 <= 0.4 + 1e-10 })
        #expect(zip(fractions, fractions.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(errors.allSatisfy { $0 < 1e-8 })
        #expect(abs(water.fraction - 0.4) < 1e-8)
        #expect(abs(water.landedFraction - 0.4) < 1e-8)
        #expect(!water.isPouring)
        #expect(water.hasMadeFirstContact)
        #expect(controls.feedback == .completed)
    }

    @Test("注水中の追加要求は最新の合計量まで続けて注ぐ")
    func requestsDuringPouringReachLatestTotal() {
        // 準備
        let controls = FluidControls(initialFraction: 0.25)
        controls.configuration.flow = 0.16
        let water = WaterModel(aspectRatio: 2.16)
        var playback = FluidPlayback()
        controls.pour(to: 0.35)
        for frame in 1...10 { playback.advance(water, controls: controls, now: Double(frame) / 60) }
        let fraction = water.fraction
        controls.pour(to: 0.5)
        controls.pour(to: 0.65)
        var fractions: [Double] = []
        var errors: [Double] = []

        // 実行
        for frame in 11...600 {
            playback.advance(water, controls: controls, now: Double(frame) / 60)
            fractions.append(water.fraction)
            errors.append(abs(water.landedFraction + water.jetFraction + water.splashFraction - water.fraction))
        }

        // 検証
        #expect(fractions.allSatisfy { $0 >= fraction && $0 <= 0.65 + 1e-10 })
        #expect(zip(fractions, fractions.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(errors.allSatisfy { $0 < 1e-8 })
        #expect(abs(water.landedFraction - 0.65) < 1e-8)
        #expect(!playback.hasPendingPour(water, controls: controls))
    }

    @Test("追加注水を繰り返しても満水を超えない")
    func repeatedAdditionsStopAtCapacity() {
        // 準備
        let controls = FluidControls(initialFraction: 0.25)
        controls.configuration.flow = 0.16
        let water = WaterModel(aspectRatio: 2.16)
        var playback = FluidPlayback()
        var frame = 0

        // 実行
        for target in [0.35, 0.5, 1.2] {
            controls.pour(to: target)
            for _ in 0..<480 {
                frame += 1
                playback.advance(water, controls: controls, now: Double(frame) / 60)
            }
        }

        // 検証
        #expect(abs(water.fraction - 1) < 1e-8)
        #expect(abs(water.landedFraction - 1) < 1e-8)
        #expect(water.depths.allSatisfy { $0.isFinite && $0 <= water.height + 1e-8 })
        #expect(controls.targetFraction == 1)
    }

    @Test("現在量以下や非有限の追加目標では水量も注水通知も変わらない",
          arguments: [0.1, 0.25, -1, Double.nan, .infinity, -.infinity])
    func invalidAdditionDoesNotPour(target: Double) {
        // 準備
        let controls = FluidControls(initialFraction: 0.25)
        let water = WaterModel(aspectRatio: 2.16)
        var playback = FluidPlayback()
        playback.advance(water, controls: controls, now: 1)

        // 実行
        controls.pour(to: target)
        playback.advance(water, controls: controls, now: 2)

        // 検証
        #expect(abs(water.fraction - 0.25) < 1e-10)
        #expect(controls.targetFraction == 0.25)
        #expect(controls.feedback == nil)
        #expect(!water.isPouring)
    }

    @Test("空にすると進行中と待機中の追加注水を取り消す")
    func resetCancelsQueuedAddition() {
        // 準備
        let controls = FluidControls(initialFraction: 0.25)
        let water = WaterModel(aspectRatio: 2.16)
        var playback = FluidPlayback()
        controls.pour(to: 0.5)
        playback.advance(water, controls: controls, now: 1)
        controls.pour(to: 0.7)
        playback.advance(water, controls: controls, now: 2)

        // 実行
        controls.reset()
        for frame in 1...120 { playback.advance(water, controls: controls, now: 2 + Double(frame) / 60) }

        // 検証
        #expect(!water.hasWater)
        #expect(!water.isPouring)
        #expect(!playback.hasPendingPour(water, controls: controls))
        #expect(water.streamVertices().isEmpty)
        #expect(controls.targetFraction == 0)
    }

    @Test("量を直接表示すると進行中と待機中の注水を取り消す")
    func showingAmountCancelsPouring() {
        // 準備
        let controls = FluidControls()
        let water = WaterModel(aspectRatio: 2.16)
        var playback = FluidPlayback()
        controls.pour()
        playback.advance(water, controls: controls, now: 1)
        controls.pour(to: 0.7)
        playback.advance(water, controls: controls, now: 2)

        // 実行
        controls.show(fraction: 0.6)
        playback.advance(water, controls: controls, now: 3)

        // 検証
        #expect(abs(water.fraction - 0.6) < 1e-10)
        #expect(abs(water.landedFraction - 0.6) < 1e-10)
        #expect(water.surfaceRange < 1e-10)
        #expect(!playback.hasPendingPour(water, controls: controls))
        #expect(!water.isPouring)
        #expect(controls.feedback == nil)
    }
}
