import Foundation
import Testing
@testable import LiquidAnimation

// モデル・操作状態・再生制御は各ケースが生成し、スコープ終了時に破棄する。
// 外部資源を変更しないため、明示的な後始末やテスト間の共有フィクスチャは不要。
@MainActor
struct LiquidAnimationTests {
    @Test("注水が落ち着くと指定量が水面内に保存され空中の水がなくなる", arguments: [0.0, 0.5, 1.0])
    func requestedVolumeRemainsAfterSettling(fill: Double) {
        // 準備
        let water = WaterModel(aspectRatio: 2.16)
        var config = FluidConfiguration()
        config.fill = fill
        config.flow = 0.16
        water.reset(configuration: config, start: true)

        // 実行
        for _ in 0..<900 { water.advance(by: 1 / 60) }

        // 検証
        #expect(abs(water.fraction - fill) < 1e-9)
        #expect(water.airborneFraction < 1e-9)
        #expect(abs(water.meanDepth / water.height - fill) < 1e-8)
    }

    @Test("指定量まで注いだ水は有限な水位を保ち静止する", arguments: [0.0, 0.5, 1.0])
    func pouredWaterSettles(fill: Double) {
        // 準備
        let water = WaterModel(aspectRatio: 2.16)
        var config = FluidConfiguration()
        config.fill = fill
        config.flow = 0.16
        water.reset(configuration: config, start: true)

        // 実行
        for _ in 0..<900 { water.advance(by: 1 / 60) }

        // 検証
        #expect(water.depths.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= water.height + 1e-9 })
        #expect(water.surfaceRange / water.height < 0.01)
        #expect(water.kineticEnergy < 1e-5)
        #expect(water.streamVertices().isEmpty)
    }

    @Test("注水中も水流・水滴・容器内の合計が投入量に一致する")
    func pouringConservesTotalVolume() {
        // 準備
        let water = WaterModel(aspectRatio: 2.16)
        water.reset(configuration: FluidConfiguration(), start: true)
        var samples: [(total: Double, accounted: Double, level: Double, landed: Double)] = []

        // 実行
        for _ in 0..<120 {
            water.advance(by: 1 / 60)
            samples.append((water.fraction, water.landedFraction + water.airborneFraction,
                            water.meanDepth / water.height, water.landedFraction))
        }

        // 検証
        for sample in samples {
            #expect(sample.total <= 0.5 + 1e-10)
            #expect(abs(sample.accounted - sample.total) < 1e-10)
            #expect(abs(sample.level - sample.landed) < 1e-8)
        }
    }

    @Test("注水開始後は落下中の水流が現れる")
    func pouringCreatesAnAirborneStream() {
        // 準備
        let water = WaterModel(aspectRatio: 2.16)
        water.reset(configuration: FluidConfiguration(), start: true)

        // 実行
        for _ in 0..<11 { water.advance(by: 1 / 60) }
        let stream = water.streamVertices()

        // 検証
        #expect(!stream.isEmpty)
    }

    @Test("注水終了後は波のエネルギーと水位差が減衰する")
    func wavesLoseEnergyAfterPouring() throws {
        // 準備
        let water = WaterModel(aspectRatio: 2.16)
        var config = FluidConfiguration()
        config.fill = 0.5
        config.flow = 0.16
        water.reset(configuration: config, start: true)
        for _ in 0..<240 { water.advance(by: 1 / 60) }
        let earlyEnergy = water.kineticEnergy
        let earlyRange = water.surfaceRange
        try #require(earlyEnergy > 0)

        // 実行
        for _ in 0..<480 { water.advance(by: 1 / 60) }

        // 検証
        #expect(water.kineticEnergy < earlyEnergy * 0.01)
        #expect(water.surfaceRange < earlyRange * 0.1)
    }

    @Test("飛沫は水を増やさずに容器内へ戻る", arguments: [-65.0, 0.0, 65.0])
    func splashReturnsWithoutAddingWater(angle: Double) {
        // 準備
        let water = WaterModel(aspectRatio: 2.16)
        var config = FluidConfiguration()
        config.angle = angle
        config.flow = 0.16
        water.reset(configuration: config, start: true)
        var sawSpray = false
        var maximumCount = 0
        var volumeErrors: [Double] = []
        var finiteCoordinates = true

        // 実行
        for _ in 0..<720 {
            water.advance(by: 1 / 60)
            sawSpray = sawSpray || water.splashCount > 0
            maximumCount = max(maximumCount, water.splashCount)
            volumeErrors.append(abs(water.jetFraction + water.splashFraction + water.landedFraction - water.fraction))
            finiteCoordinates = finiteCoordinates && water.splashVertices().allSatisfy {
                $0.position.x.isFinite && $0.position.y.isFinite
            }
        }

        // 検証
        #expect(sawSpray)
        #expect(maximumCount <= WaterModel.maximumDrops)
        #expect(volumeErrors.allSatisfy { $0 < 1e-9 })
        #expect(finiteCoordinates)
        #expect(water.splashCount == 0)
        #expect(abs(water.landedFraction - 0.5) < 1e-9)
    }

    @Test("鉛直に注ぐと着水点の水面が両脇よりへこむ")
    func impactDepressesSurface() {
        // 準備
        let water = WaterModel(aspectRatio: 2.16)
        var config = FluidConfiguration()
        config.angle = 0
        water.reset(configuration: config, start: true)

        // 実行
        for _ in 0..<180 { water.advance(by: 1 / 60) }
        let center = Int(config.sourcePosition * Double(water.columnCount))
        let shoulderDepth = (water.depths[center - 7] + water.depths[center + 7]) / 2

        // 検証
        #expect(water.impactPressure[center] > 0.05)
        #expect(shoulderDepth - water.depths[center] > 0.002)
        #expect(abs(water.meanDepth / water.height - water.landedFraction) < 1e-8)
    }

    @Test("鉛直に注ぐ水流の先端は着水した水面につながる")
    func fallingStreamConnectsToWaterSurface() throws {
        // 準備
        let water = WaterModel(aspectRatio: 2.16)
        var config = FluidConfiguration()
        config.angle = 0
        water.reset(configuration: config, start: true)

        // 実行
        for _ in 0..<180 { water.advance(by: 1 / 60) }
        let stream = water.streamVertices()

        // 検証
        try #require(stream.count >= 2)
        let head = (stream[stream.count - 1].position + stream[stream.count - 2].position) / 2
        let column = min(water.columnCount - 1, max(0, Int(Double(head.x) * Double(water.columnCount))))
        #expect(Double(head.y) <= water.depths[column] / water.height + 0.002)
    }

    @Test("注水終了後は着水圧力が消え水面が落ち着く")
    func impactPressureFadesAfterPouring() throws {
        // 準備
        let water = WaterModel(aspectRatio: 2.16)
        var configuration = FluidConfiguration()
        configuration.angle = 0
        water.reset(configuration: configuration, start: true)
        for _ in 0..<180 { water.advance(by: 1 / 60) }
        try #require((water.impactPressure.max() ?? 0) > 0.05)

        // 実行
        for _ in 0..<540 { water.advance(by: 1 / 60) }

        // 検証
        #expect((water.impactPressure.max() ?? 0) < 1e-8)
        #expect(water.surfaceRange / water.height < 0.01)
    }

    @Test("注水の開始と終了は最大流量より小さく対称に増減する", arguments: [0.001, 0.5])
    func inletRampsAtBothEnds(fill: Double) {
        // 準備
        let water = WaterModel(aspectRatio: 2.16)
        var config = FluidConfiguration()
        config.fill = fill
        config.flow = 0.16
        water.reset(configuration: config, start: true)
        let duration = water.pourDuration
        let ramp = min(0.25, fill / config.flow)
        func advance(to instant: Double) {
            while water.time < instant - 1e-9 { water.advance(by: min(1 / 60, instant - water.time)) }
        }

        // 実行
        advance(to: ramp / 4)
        let startRate = water.inletRate
        advance(to: duration / 2)
        let peakRate = water.inletRate
        advance(to: duration - ramp / 4)

        // 検証
        #expect(startRate > 0 && startRate < peakRate * 0.25)
        #expect(abs(water.inletRate - startRate) < 1e-9)
        #expect(water.fraction < fill)
    }

    @Test("注水が完了すると流入を止めて指定量を過不足なく届ける", arguments: [0.001, 0.5])
    func completedPourDeliversRequestedVolume(fill: Double) {
        // 準備
        let water = WaterModel(aspectRatio: 2.16)
        var config = FluidConfiguration()
        config.fill = fill
        config.flow = 0.16
        water.reset(configuration: config, start: true)
        let finish = water.pourDuration + 1

        // 実行
        while water.time < finish - 1e-9 { water.advance(by: min(1 / 60, finish - water.time)) }

        // 検証
        #expect(water.inletRate == 0)
        #expect(abs(water.fraction - fill) < 1e-9)
        #expect(abs(water.landedFraction - fill) < 1e-9)
    }

    @Test("注水中の水流の入口は容器の上辺より外にある", arguments: [0.001, 0.5])
    func streamStartsAboveContainer(fill: Double) throws {
        // 準備
        let water = WaterModel(aspectRatio: 2.16)
        var config = FluidConfiguration()
        config.fill = fill
        config.flow = 0.16
        water.reset(configuration: config, start: true)
        let midpoint = water.pourDuration / 2

        // 実行
        while water.time < midpoint - 1e-9 { water.advance(by: min(1 / 60, midpoint - water.time)) }
        let jet = water.streamVertices()

        // 検証
        try #require(jet.count >= 2)
        #expect(jet.count <= WaterModel.maximumStreamVertices)
        #expect(jet[0].position.y > 1 && jet[1].position.y > 1)
    }

    @Test("満水に近づいても波高と1フレームの水位変化が上限内に収まる", arguments: [0.08, 0.16])
    func fullTankApproachRemainsStable(flow: Double) {
        // 準備
        let water = WaterModel(aspectRatio: 2.16)
        var config = FluidConfiguration()
        config.fill = 1
        config.flow = flow
        water.reset(configuration: config, start: true)
        var lateRange = 0.0
        var lateJump = 0.0
        var previous = water.depths
        var volumeErrors: [Double] = []
        var validDepths = true

        // 実行
        for _ in 0..<960 {
            water.advance(by: 1 / 60)
            if water.landedFraction >= 0.85 {
                lateRange = max(lateRange, water.surfaceRange / water.height)
                lateJump = max(lateJump, zip(water.depths, previous).map { abs($0 - $1) / water.height }.max() ?? 0)
                volumeErrors.append(abs(water.meanDepth / water.height - water.landedFraction))
                validDepths = validDepths && water.depths.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= water.height + 1e-9 }
            }
            previous = water.depths
        }

        // 検証
        #expect(!volumeErrors.isEmpty)
        #expect(volumeErrors.allSatisfy { $0 < 1e-8 })
        #expect(validDepths)
        #expect(lateRange < 0.04)
        #expect(lateJump < 0.01)
        #expect(abs(water.landedFraction - 1) < 1e-9)
    }

    @Test("着水で発生した気泡は水量を変えずに消える")
    func bubblesDisappearWithoutChangingVolume() {
        // 準備
        let water = WaterModel(aspectRatio: 2.16)
        var config = FluidConfiguration()
        config.flow = 0.16
        water.reset(configuration: config, start: true)
        var maximumCount = 0
        var volumeErrors: [Double] = []
        var validVertices = true

        // 実行
        for _ in 0..<480 {
            water.advance(by: 1 / 60)
            maximumCount = max(maximumCount, water.bubbleCount)
            volumeErrors.append(abs(water.jetFraction + water.splashFraction + water.landedFraction - water.fraction))
            validVertices = validVertices && water.bubbleVertices().allSatisfy {
                $0.position.x.isFinite && $0.position.y.isFinite &&
                $0.appearance.x >= 0 && $0.appearance.x <= 1
            }
        }

        // 検証
        #expect(maximumCount > 0)
        #expect(maximumCount <= WaterModel.maximumBubbles)
        #expect(volumeErrors.allSatisfy { $0 < 1e-9 })
        #expect(validVertices)
        #expect(water.bubbleCount == 0)
        #expect(abs(water.landedFraction - 0.5) < 1e-9)
    }

    @Test("注ぎ終わりの水流は最大3滴に分かれ水量を変えずに戻る", arguments: [0.08, 0.16])
    func tailSeparatesWithoutChangingVolume(flow: Double) {
        // 準備
        let water = WaterModel(aspectRatio: 2.16)
        var config = FluidConfiguration()
        config.flow = flow
        water.reset(configuration: config, start: true)
        var maximumDetached = 0
        var volumeErrors: [Double] = []
        var streamCounts: [Int] = []

        // 実行
        for _ in 0..<600 {
            water.advance(by: 1 / 60)
            maximumDetached = max(maximumDetached, water.detachedDropCount)
            volumeErrors.append(abs(water.jetFraction + water.splashFraction + water.landedFraction - water.fraction))
            streamCounts.append(water.streamVertices().count)
        }

        // 検証
        #expect(maximumDetached > 0)
        #expect(maximumDetached <= 3)
        #expect(volumeErrors.allSatisfy { $0 < 1e-9 })
        #expect(streamCounts.allSatisfy { $0 <= WaterModel.maximumStreamVertices })
        #expect(water.separatedTailArea > 0)
        #expect(water.detachedDropCount == 0)
        #expect(abs(water.landedFraction - config.fill) < 1e-9)
    }

}

struct FluidConfigurationTests {
    @Test("範囲外の設定値は対応する上下限に補正する", arguments: [-100.0, 100.0])
    func outOfRangeSettingsAreClamped(input: Double) {
        // 準備
        var configuration = FluidConfiguration()
        configuration.fill = input
        configuration.opacity = input
        configuration.sourcePosition = input
        configuration.angle = input
        configuration.flow = input

        // 実行
        let actual = configuration.sanitized

        // 検証
        #expect(actual.fill == (input < 0 ? 0 : 1))
        #expect(actual.opacity == (input < 0 ? 0 : 1))
        #expect(actual.sourcePosition == (input < 0 ? 0.15 : 0.85))
        #expect(actual.angle == (input < 0 ? -65 : 65))
        #expect(actual.flow == (input < 0 ? 0.02 : 0.16))
    }

    @Test("非有限な設定値は既定値に戻す", arguments: [Double.nan, .infinity, -.infinity])
    func nonfiniteSettingsUseDefaults(input: Double) {
        // 準備
        var configuration = FluidConfiguration()
        configuration.fill = input
        configuration.opacity = input
        configuration.sourcePosition = input
        configuration.angle = input
        configuration.flow = input

        // 実行
        let actual = configuration.sanitized

        // 検証
        #expect(actual == FluidConfiguration())
    }

    @Test("範囲内の設定値は補正しても変わらない")
    func validSettingsRemainUnchanged() {
        // 準備
        var configuration = FluidConfiguration()
        configuration.fill = 0.7
        configuration.opacity = 0.3
        configuration.sourcePosition = 0.6
        configuration.angle = -20
        configuration.flow = 0.12

        // 実行
        let actual = configuration.sanitized

        // 検証
        #expect(actual == configuration)
    }
}

@MainActor
struct FluidControlsTests {
    @Test("一時停止中に注水を要求すると再生を再開する")
    func pourResumesPlayback() {
        // 準備
        let controls = FluidControls()
        controls.isPaused = true

        // 実行
        controls.pour()

        // 検証
        #expect(!controls.isPaused)
    }

    @Test("注水を要求するたびにリセットとは別の再注水要求を発行する")
    func repeatedPoursIssueNewRestartRequests() {
        // 準備
        let controls = FluidControls()
        controls.pour()
        let previousRestart = controls.restartID
        let previousReset = controls.resetID

        // 実行
        controls.pour()

        // 検証
        #expect(previousRestart > 0)
        #expect(controls.restartID == previousRestart + 1)
        #expect(controls.resetID == previousReset)
    }

    @Test("一時停止中にリセットすると空の初期表示で再生を再開する")
    func resetRestoresInitialPlaybackDisplay() {
        // 準備
        let controls = FluidControls()
        controls.isPaused = true
        controls.insertedFraction = 0.4
        controls.status = "一時停止中"

        // 実行
        controls.reset()

        // 検証
        #expect(!controls.isPaused)
        #expect(controls.insertedFraction == 0)
        #expect(controls.status == "注水して動きを確認")
    }

    @Test("リセットは注水設定と再注水要求を変更しない")
    func resetPreservesPourConfiguration() {
        // 準備
        let controls = FluidControls()
        controls.configuration.fill = 0.8
        let configuration = controls.configuration
        let restart = controls.restartID

        // 実行
        controls.reset()

        // 検証
        #expect(controls.configuration == configuration)
        #expect(controls.restartID == restart)
    }

    @Test("リセットを要求するたびに新しいリセット要求を発行する")
    func repeatedResetsIssueNewResetRequests() {
        // 準備
        let controls = FluidControls()
        controls.reset()
        let previousReset = controls.resetID

        // 実行
        controls.reset()

        // 検証
        #expect(controls.resetID == previousReset + 1)
    }
}

@MainActor
struct WaterModelInputTests {
    @Test("0・負数・非有限の時間を渡してもシミュレーション状態は変わらない", arguments: [0.0, -1.0, .nan, .infinity, -.infinity])
    func invalidDurationsLeaveStateUnchanged(duration: Double) {
        // 準備
        let water = WaterModel(aspectRatio: 2.16)
        water.reset(configuration: FluidConfiguration(), start: true)
        for _ in 0..<120 { water.advance(by: 1 / 60) }
        let time = water.time
        let fraction = water.fraction
        let depths = water.depths
        let pressure = water.impactPressure
        let drops = water.splashCount
        let bubbles = water.bubbleCount

        // 実行
        water.advance(by: duration)

        // 検証
        #expect(water.time == time)
        #expect(water.fraction == fraction)
        #expect(water.depths == depths)
        #expect(water.impactPressure == pressure)
        #expect(water.splashCount == drops)
        #expect(water.bubbleCount == bubbles)
    }

    @Test("長い遅延を渡しても1回の更新は最大1/30秒に制限する")
    func delayedUpdateIsBounded() {
        // 準備
        let delayed = WaterModel(aspectRatio: 2.16)
        let bounded = WaterModel(aspectRatio: 2.16)
        delayed.reset(configuration: FluidConfiguration(), start: true)
        bounded.reset(configuration: FluidConfiguration(), start: true)

        // 実行
        delayed.advance(by: 10)
        bounded.advance(by: 1 / 30)

        // 検証
        #expect(abs(delayed.time - 1 / 30) < 1e-12)
        #expect(delayed.time == bounded.time)
        #expect(delayed.fraction == bounded.fraction)
        #expect(delayed.depths == bounded.depths)
    }

    @Test("リセットは水・気泡・着水圧力・分離した末尾の状態をすべて消す", arguments: [120, 214])
    func resetClearsAllSimulationState(frames: Int) throws {
        // 準備
        let water = WaterModel(aspectRatio: 2.16)
        var configuration = FluidConfiguration()
        configuration.flow = 0.16
        water.reset(configuration: configuration, start: true)
        for _ in 0..<frames { water.advance(by: 1 / 60) }
        try #require(water.hasWater)
        try #require(water.bubbleCount > 0)

        // 実行
        water.reset(configuration: configuration, start: false)

        // 検証
        #expect(!water.hasWater)
        #expect(!water.isPouring)
        #expect(water.time == 0)
        #expect(water.fraction == 0)
        #expect(water.airborneFraction == 0)
        #expect(water.separatedTailArea == 0)
        #expect(water.detachedDropCount == 0)
        #expect(water.depths.allSatisfy { $0 == 0 })
        #expect(water.impactPressure.allSatisfy { $0 == 0 })
        #expect(water.streamVertices().isEmpty)
        #expect(water.splashVertices().isEmpty)
        #expect(water.bubbleVertices().isEmpty)
    }

    @Test("不透明度を変えても物理計算の結果は変わらない")
    func opacityDoesNotChangePhysics() {
        // 準備
        let transparent = WaterModel(aspectRatio: 2.16)
        let opaque = WaterModel(aspectRatio: 2.16)
        var configuration = FluidConfiguration()
        configuration.opacity = 0
        transparent.reset(configuration: configuration, start: true)
        configuration.opacity = 1
        opaque.reset(configuration: configuration, start: true)

        // 実行
        for _ in 0..<120 {
            transparent.advance(by: 1 / 60)
            opaque.advance(by: 1 / 60)
        }

        // 検証
        #expect(transparent.depths == opaque.depths)
        #expect(transparent.fraction == opaque.fraction)
        #expect(transparent.impactPressure == opaque.impactPressure)
        #expect(transparent.bubbleCount == opaque.bubbleCount)
    }
}

@MainActor
struct FluidPlaybackTests {
    @Test("一時停止中は水と泡の状態が変わらない", arguments: [FluidKind.water, .beer])
    func pauseFreezesWaterAndFoam(kind: FluidKind) {
        // 準備
        let controls = FluidControls()
        controls.configuration.kind = kind
        let water = WaterModel(aspectRatio: 2.16)
        var playback = FluidPlayback()
        controls.pour()
        for frame in 1...90 { playback.advance(water, controls: controls, now: Double(frame) / 60) }
        let time = water.time
        let depths = water.depths
        let fraction = water.fraction
        let pressure = water.impactPressure
        let bubbles = water.bubbleVertices().map(\.position)
        let foam = water.foamLiquidArea
        let cloudiness = water.beerCloudiness
        controls.isPaused = true

        // 実行
        playback.advance(water, controls: controls, now: 10)

        // 検証
        #expect(water.time == time)
        #expect(water.depths == depths)
        #expect(water.fraction == fraction)
        #expect(water.impactPressure == pressure)
        #expect(water.bubbleVertices().map(\.position) == bubbles)
        #expect(water.foamLiquidArea == foam)
        #expect(water.beerCloudiness == cloudiness)
    }

    @Test("一時停止から再開しても停止時間の追いつき計算をしない", arguments: [FluidKind.water, .beer])
    func resumeSkipsPausedElapsedTime(kind: FluidKind) {
        // 準備
        let controls = FluidControls()
        controls.configuration.kind = kind
        let water = WaterModel(aspectRatio: 2.16)
        var playback = FluidPlayback()
        controls.pour()
        for frame in 1...90 { playback.advance(water, controls: controls, now: Double(frame) / 60) }
        controls.isPaused = true
        playback.advance(water, controls: controls, now: 10)
        let time = water.time
        let fraction = water.fraction
        controls.isPaused = false

        // 実行
        playback.advance(water, controls: controls, now: 20)

        // 検証
        #expect(abs(water.time - time - 1 / 60) < 1e-8)
        #expect(water.fraction > fraction)
    }

    @Test("リセットは未処理の再注水要求も消費して容器を空に保つ")
    func resetConsumesPendingRestarts() throws {
        // 準備
        let controls = FluidControls()
        let water = WaterModel(aspectRatio: 2.16)
        var playback = FluidPlayback()
        controls.pour()
        playback.advance(water, controls: controls, now: 1)
        try #require(water.hasWater)
        controls.pour()

        // 実行
        controls.reset()
        playback.advance(water, controls: controls, now: 2)
        playback.advance(water, controls: controls, now: 3)

        // 検証
        #expect(!water.hasWater)
        #expect(!water.isPouring)
        #expect(water.time == 0)
    }

    @Test("設定を編集しただけでは進行中の注水条件を変えない")
    func editingSettingsDoesNotChangeCurrentPour() throws {
        // 準備
        let controls = FluidControls()
        let water = WaterModel(aspectRatio: 2.16)
        var playback = FluidPlayback()
        controls.pour()
        for frame in 1...60 { playback.advance(water, controls: controls, now: Double(frame) / 60) }
        try #require(water.time > 0.9)
        let originalConfiguration = water.configuration

        // 実行
        controls.configuration.fill = 0.25
        controls.configuration.angle = -30
        controls.configuration.kind = .beer

        playback.advance(water, controls: controls, now: 2)

        // 検証
        #expect(water.configuration == originalConfiguration)
    }

    @Test("再注水すると編集した設定を適用して時刻を最初から進める")
    func restartingAppliesEditedSettings() {
        // 準備
        let controls = FluidControls()
        let water = WaterModel(aspectRatio: 2.16)
        var playback = FluidPlayback()
        controls.pour()
        for frame in 1...60 { playback.advance(water, controls: controls, now: Double(frame) / 60) }
        controls.configuration.fill = 0.25
        controls.configuration.angle = -30
        controls.configuration.kind = .beer

        // 実行
        controls.pour()
        playback.advance(water, controls: controls, now: 3)

        // 検証
        #expect(water.configuration.fill == 0.25)
        #expect(water.configuration.angle == -30)
        #expect(water.configuration.kind == .beer)
        #expect(abs(water.time - 1 / 60) < 1e-8)
    }

    @Test("再注水要求の適用後は毎フレーム時刻をリセットしない")
    func restartRequestIsConsumedOnce() {
        // 準備
        let controls = FluidControls()
        let water = WaterModel(aspectRatio: 2.16)
        var playback = FluidPlayback()
        controls.configuration.fill = 0.25
        controls.pour()
        playback.advance(water, controls: controls, now: 3)
        let previousTime = water.time

        // 実行
        playback.advance(water, controls: controls, now: 4)

        // 検証
        #expect(previousTime > 0)
        #expect(water.time > previousTime)
    }
}
