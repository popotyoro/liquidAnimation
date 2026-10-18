import Foundation
import Testing
@testable import LiquidAnimation

@MainActor
struct LiquidAnimationTests {
    @Test("注水が落ち着くと指定量が水面内に保存され空中の水がなくなる", arguments: [0.0, 0.5, 1.0])
    func requestedVolumeRemainsAfterSettling(fill: Double) {
        let water = WaterModel(aspectRatio: 2.16)
        var config = FluidConfiguration()
        config.fill = fill
        config.flow = 0.16
        water.reset(configuration: config, start: true)
        for _ in 0..<900 { water.advance(by: 1 / 60) }
        #expect(abs(water.fraction - fill) < 1e-9)
        #expect(water.airborneFraction < 1e-9)
        #expect(abs(water.meanDepth / water.height - fill) < 1e-8)
        #expect(water.depths.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= water.height + 1e-9 })
        #expect(water.surfaceRange / water.height < 0.01)
        #expect(water.kineticEnergy < 1e-5)
        #expect(water.streamVertices().isEmpty)
    }

    @Test("注水中も水流・水滴・容器内の合計が投入量に一致する")
    func pouringConservesTotalVolume() {
        let water = WaterModel(aspectRatio: 2.16)
        water.reset(configuration: FluidConfiguration(), start: true)
        for frame in 0..<120 {
            water.advance(by: 1 / 60)
            #expect(water.fraction <= 0.5 + 1e-10)
            #expect(abs(water.landedFraction + water.airborneFraction - water.fraction) < 1e-10)
            #expect(abs(water.meanDepth / water.height - water.landedFraction) < 1e-8)
            if frame == 10 { #expect(!water.streamVertices().isEmpty) }
        }
    }

    @Test("注水終了後は波のエネルギーと水位差が減衰する")
    func wavesLoseEnergyAfterPouring() {
        let water = WaterModel(aspectRatio: 2.16)
        var config = FluidConfiguration()
        config.fill = 0.5
        config.flow = 0.16
        water.reset(configuration: config, start: true)
        for _ in 0..<240 { water.advance(by: 1 / 60) }
        let earlyEnergy = water.kineticEnergy
        let earlyRange = water.surfaceRange
        for _ in 0..<480 { water.advance(by: 1 / 60) }
        #expect(earlyEnergy > 0)
        #expect(water.kineticEnergy < earlyEnergy * 0.01)
        #expect(water.surfaceRange < earlyRange * 0.1)
    }

    @Test("飛沫は水を増やさずに容器内へ戻る", arguments: [-65.0, 0.0, 65.0])
    func splashReturnsWithoutAddingWater(angle: Double) {
        let water = WaterModel(aspectRatio: 2.16)
        var config = FluidConfiguration()
        config.angle = angle
        config.flow = 0.16
        water.reset(configuration: config, start: true)
        var sawSpray = false
        for _ in 0..<720 {
            water.advance(by: 1 / 60)
            sawSpray = sawSpray || water.splashCount > 0
            #expect(water.splashCount <= WaterModel.maximumDrops)
            #expect(abs(water.jetFraction + water.splashFraction + water.landedFraction - water.fraction) < 1e-9)
            #expect(water.splashVertices().allSatisfy {
                $0.position.x.isFinite && $0.position.y.isFinite
            })
        }
        #expect(sawSpray)
        #expect(water.splashCount == 0)
        #expect(abs(water.landedFraction - 0.5) < 1e-9)
    }

    @Test("注水中は着水点がへこみ水流の先端が水面につながる")
    func impactDepressesSurfaceAndConnectsJet() {
        let water = WaterModel(aspectRatio: 2.16)
        var config = FluidConfiguration()
        config.angle = 0
        water.reset(configuration: config, start: true)
        for _ in 0..<180 { water.advance(by: 1 / 60) }
        let center = Int(config.sourcePosition * Double(water.columnCount))
        let shoulderDepth = (water.depths[center - 7] + water.depths[center + 7]) / 2
        #expect(water.impactPressure[center] > 0.05)
        #expect(shoulderDepth - water.depths[center] > 0.002)
        #expect(abs(water.meanDepth / water.height - water.landedFraction) < 1e-8)
        let stream = water.streamVertices()
        #expect(stream.count >= 2)
        if stream.count >= 2 {
            let head = (stream[stream.count - 1].position + stream[stream.count - 2].position) / 2
            let column = min(water.columnCount - 1, max(0, Int(Double(head.x) * Double(water.columnCount))))
            #expect(Double(head.y) <= water.depths[column] / water.height + 0.002)
        }
    }

    @Test("注水終了後は着水圧力が消え水面が落ち着く")
    func impactPressureFadesAfterPouring() {
        let water = WaterModel(aspectRatio: 2.16)
        var configuration = FluidConfiguration()
        configuration.angle = 0
        water.reset(configuration: configuration, start: true)
        for _ in 0..<180 { water.advance(by: 1 / 60) }
        #expect((water.impactPressure.max() ?? 0) > 0.05)

        for _ in 0..<540 { water.advance(by: 1 / 60) }

        #expect((water.impactPressure.max() ?? 0) < 1e-8)
        #expect(water.surfaceRange / water.height < 0.01)
    }

    @Test("注水の開始と終了は流量を減らし指定量を過不足なく投入する", arguments: [0.001, 0.5])
    func inletRampsWhileDeliveringRequestedVolume(fill: Double) {
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
        advance(to: ramp / 4)
        let startRate = water.inletRate
        advance(to: duration / 2)
        let peakRate = water.inletRate
        #expect(startRate > 0 && startRate < peakRate * 0.25)
        let jet = water.streamVertices()
        #expect(jet.count <= WaterModel.maximumStreamVertices)
        #expect(jet.count >= 2)
        if jet.count >= 2 { #expect(jet[0].position.y > 1 && jet[1].position.y > 1) }
        advance(to: duration - ramp / 4)
        #expect(abs(water.inletRate - startRate) < 1e-9)
        #expect(water.fraction < fill)
        advance(to: duration + 1)
        #expect(water.inletRate == 0)
        #expect(abs(water.fraction - fill) < 1e-9)
        #expect(abs(water.landedFraction - fill) < 1e-9)
    }

    @Test("満水に近づいても波高と1フレームの水位変化が上限内に収まる", arguments: [0.08, 0.16])
    func fullTankApproachRemainsStable(flow: Double) {
        let water = WaterModel(aspectRatio: 2.16)
        var config = FluidConfiguration()
        config.fill = 1
        config.flow = flow
        water.reset(configuration: config, start: true)
        var lateRange = 0.0
        var lateJump = 0.0
        var previous = water.depths
        for _ in 0..<960 {
            water.advance(by: 1 / 60)
            if water.landedFraction >= 0.85 {
                lateRange = max(lateRange, water.surfaceRange / water.height)
                lateJump = max(lateJump, zip(water.depths, previous).map { abs($0 - $1) / water.height }.max() ?? 0)
                #expect(abs(water.meanDepth / water.height - water.landedFraction) < 1e-8)
                #expect(water.depths.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= water.height + 1e-9 })
            }
            previous = water.depths
        }
        #expect(lateRange < 0.04)
        #expect(lateJump < 0.01)
        #expect(abs(water.landedFraction - 1) < 1e-9)
    }

    @Test("気泡は個数上限を守り水量を変えずに消える")
    func bubblesDisappearWithoutChangingVolume() {
        let water = WaterModel(aspectRatio: 2.16)
        var config = FluidConfiguration()
        config.flow = 0.16
        water.reset(configuration: config, start: true)
        var maximumCount = 0
        for _ in 0..<480 {
            water.advance(by: 1 / 60)
            maximumCount = max(maximumCount, water.bubbleCount)
            #expect(water.bubbleCount <= WaterModel.maximumBubbles)
            #expect(abs(water.jetFraction + water.splashFraction + water.landedFraction - water.fraction) < 1e-9)
            #expect(water.bubbleVertices().allSatisfy {
                $0.position.x.isFinite && $0.position.y.isFinite &&
                $0.appearance.x >= 0 && $0.appearance.x <= 1
            })
        }
        #expect(maximumCount > 0)
        #expect(water.bubbleCount == 0)
        #expect(abs(water.landedFraction - 0.5) < 1e-9)
    }

    @Test("注ぎ終わりの水流は最大3滴に分かれ水量を変えずに戻る", arguments: [0.08, 0.16])
    func tailSeparatesWithoutChangingVolume(flow: Double) {
        let water = WaterModel(aspectRatio: 2.16)
        var config = FluidConfiguration()
        config.flow = flow
        water.reset(configuration: config, start: true)
        var maximumDetached = 0
        for _ in 0..<600 {
            water.advance(by: 1 / 60)
            maximumDetached = max(maximumDetached, water.detachedDropCount)
            #expect(water.detachedDropCount <= 3)
            #expect(abs(water.jetFraction + water.splashFraction + water.landedFraction - water.fraction) < 1e-9)
            #expect(water.streamVertices().count <= WaterModel.maximumStreamVertices)
        }
        #expect(maximumDetached > 0)
        #expect(water.separatedTailArea > 0)
        #expect(water.detachedDropCount == 0)
        #expect(abs(water.landedFraction - config.fill) < 1e-9)
    }

}

struct FluidConfigurationTests {
    @Test("範囲外の設定値は対応する上下限に補正する", arguments: [-100.0, 100.0])
    func outOfRangeSettingsAreClamped(input: Double) {
        var configuration = FluidConfiguration()
        configuration.fill = input
        configuration.opacity = input
        configuration.sourcePosition = input
        configuration.angle = input
        configuration.flow = input

        let actual = configuration.sanitized

        #expect(actual.fill == (input < 0 ? 0 : 1))
        #expect(actual.opacity == (input < 0 ? 0 : 1))
        #expect(actual.sourcePosition == (input < 0 ? 0.15 : 0.85))
        #expect(actual.angle == (input < 0 ? -65 : 65))
        #expect(actual.flow == (input < 0 ? 0.02 : 0.16))
    }

    @Test("非有限な設定値は既定値に戻す", arguments: [Double.nan, .infinity, -.infinity])
    func nonfiniteSettingsUseDefaults(input: Double) {
        var configuration = FluidConfiguration()
        configuration.fill = input
        configuration.opacity = input
        configuration.sourcePosition = input
        configuration.angle = input
        configuration.flow = input

        #expect(configuration.sanitized == FluidConfiguration())
    }

    @Test("範囲内の設定値は補正しても変わらない")
    func validSettingsRemainUnchanged() {
        var configuration = FluidConfiguration()
        configuration.fill = 0.7
        configuration.opacity = 0.3
        configuration.sourcePosition = 0.6
        configuration.angle = -20
        configuration.flow = 0.12

        #expect(configuration.sanitized == configuration)
    }
}

@MainActor
struct FluidControlsTests {
    @Test("注水操作は毎回再生を再開して新しい再注水要求を発行する")
    func pourResumesAndIssuesRestart() {
        let controls = FluidControls()
        controls.isPaused = true
        let originalReset = controls.resetID

        controls.pour()
        let firstRestart = controls.restartID
        controls.isPaused = true
        controls.pour()

        #expect(firstRestart > 0)
        #expect(controls.restartID == firstRestart + 1)
        #expect(!controls.isPaused)
        #expect(controls.resetID == originalReset)
    }

    @Test("リセット操作は再生を再開して投入表示を消し設定は保持する")
    func resetClearsDisplayAndPreservesSettings() {
        let controls = FluidControls()
        controls.configuration.fill = 0.8
        let configuration = controls.configuration
        controls.isPaused = true
        controls.insertedFraction = 0.4
        controls.status = "一時停止中"

        controls.reset()
        let firstReset = controls.resetID
        controls.reset()

        #expect(controls.resetID == firstReset + 1)
        #expect(!controls.isPaused)
        #expect(controls.insertedFraction == 0)
        #expect(controls.status == "注水して動きを確認")
        #expect(controls.configuration == configuration)
        #expect(controls.restartID == 0)
    }
}

@MainActor
struct WaterModelInputTests {
    @Test("0・負数・非有限の時間を渡してもシミュレーション状態は変わらない", arguments: [0.0, -1.0, .nan, .infinity, -.infinity])
    func invalidDurationsLeaveStateUnchanged(duration: Double) {
        let water = WaterModel(aspectRatio: 2.16)
        water.reset(configuration: FluidConfiguration(), start: true)
        for _ in 0..<120 { water.advance(by: 1 / 60) }
        let time = water.time
        let fraction = water.fraction
        let depths = water.depths
        let pressure = water.impactPressure
        let drops = water.splashCount
        let bubbles = water.bubbleCount

        water.advance(by: duration)

        #expect(water.time == time)
        #expect(water.fraction == fraction)
        #expect(water.depths == depths)
        #expect(water.impactPressure == pressure)
        #expect(water.splashCount == drops)
        #expect(water.bubbleCount == bubbles)
    }

    @Test("長い遅延を渡しても1回の更新は最大1/30秒に制限する")
    func delayedUpdateIsBounded() {
        let delayed = WaterModel(aspectRatio: 2.16)
        let bounded = WaterModel(aspectRatio: 2.16)
        delayed.reset(configuration: FluidConfiguration(), start: true)
        bounded.reset(configuration: FluidConfiguration(), start: true)

        delayed.advance(by: 10)
        bounded.advance(by: 1 / 30)

        #expect(abs(delayed.time - 1 / 30) < 1e-12)
        #expect(delayed.time == bounded.time)
        #expect(delayed.fraction == bounded.fraction)
        #expect(delayed.depths == bounded.depths)
    }

    @Test("リセットは水・気泡・着水圧力・分離した末尾の状態をすべて消す", arguments: [120, 214])
    func resetClearsAllSimulationState(frames: Int) {
        let water = WaterModel(aspectRatio: 2.16)
        var configuration = FluidConfiguration()
        configuration.flow = 0.16
        water.reset(configuration: configuration, start: true)
        for _ in 0..<frames { water.advance(by: 1 / 60) }
        #expect(water.hasWater)
        #expect(water.bubbleCount > 0)

        water.reset(configuration: configuration, start: false)

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
        let transparent = WaterModel(aspectRatio: 2.16)
        let opaque = WaterModel(aspectRatio: 2.16)
        var configuration = FluidConfiguration()
        configuration.opacity = 0
        transparent.reset(configuration: configuration, start: true)
        configuration.opacity = 1
        opaque.reset(configuration: configuration, start: true)

        for _ in 0..<120 {
            transparent.advance(by: 1 / 60)
            opaque.advance(by: 1 / 60)
        }

        #expect(transparent.depths == opaque.depths)
        #expect(transparent.fraction == opaque.fraction)
        #expect(transparent.impactPressure == opaque.impactPressure)
        #expect(transparent.bubbleCount == opaque.bubbleCount)
    }
}

@MainActor
struct FluidPlaybackTests {
    @Test("一時停止は水の状態を固定し再開時に停止時間の追いつき計算をしない")
    func pauseFreezesStateAndResumeSkipsElapsedTime() {
        let controls = FluidControls()
        let water = WaterModel(aspectRatio: 2.16)
        var playback = FluidPlayback()
        controls.pour()
        for frame in 1...90 { playback.advance(water, controls: controls, now: Double(frame) / 60) }
        let time = water.time
        let depths = water.depths
        let fraction = water.fraction
        let pressure = water.impactPressure
        let bubbles = water.bubbleVertices().map(\.position)

        controls.isPaused = true
        playback.advance(water, controls: controls, now: 10)

        #expect(water.time == time)
        #expect(water.depths == depths)
        #expect(water.fraction == fraction)
        #expect(water.impactPressure == pressure)
        #expect(water.bubbleVertices().map(\.position) == bubbles)

        controls.isPaused = false
        playback.advance(water, controls: controls, now: 20)

        #expect(abs(water.time - time - 1 / 60) < 1e-8)
        #expect(water.fraction > fraction)
    }

    @Test("リセットは未処理の再注水要求も消費して容器を空に保つ")
    func resetConsumesPendingRestarts() {
        let controls = FluidControls()
        let water = WaterModel(aspectRatio: 2.16)
        var playback = FluidPlayback()
        controls.pour()
        playback.advance(water, controls: controls, now: 1)
        #expect(water.hasWater)

        controls.pour()
        controls.reset()
        playback.advance(water, controls: controls, now: 2)
        playback.advance(water, controls: controls, now: 3)

        #expect(!water.hasWater)
        #expect(!water.isPouring)
        #expect(water.time == 0)
    }

    @Test("設定変更は再注水で一度だけ確定し後続フレームで時刻が進む")
    func pourAppliesSettingsOnce() {
        let controls = FluidControls()
        let water = WaterModel(aspectRatio: 2.16)
        var playback = FluidPlayback()
        controls.pour()
        for frame in 1...60 { playback.advance(water, controls: controls, now: Double(frame) / 60) }
        #expect(water.time > 0.9)
        controls.configuration.fill = 0.25
        controls.configuration.angle = -30

        // 設定編集だけでは進行中の注水条件を変えず、再注水で確定する。
        playback.advance(water, controls: controls, now: 2)
        #expect(water.configuration.fill == 0.5)
        controls.pour()
        playback.advance(water, controls: controls, now: 3)

        #expect(water.configuration.fill == 0.25)
        #expect(water.configuration.angle == -30)
        #expect(abs(water.time - 1 / 60) < 1e-8)
        playback.advance(water, controls: controls, now: 4)
        #expect(water.time > 1 / 60)
    }
}
