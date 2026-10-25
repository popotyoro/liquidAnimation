import Testing
@testable import LiquidFluid

/// 各ケースと引数の組み合わせが専用のモデルを作る。
/// モデルは外部資源を持たないため、後始末はローカル参照の破棄で完了する。
@MainActor
struct FluidPresetTests {
    @Test("ビールは注水終了から10秒で表面の泡の保持液量が30パーセント未満へ減る")
    func beerFoamDrainsAfterPouring() throws {
        // 準備
        let water = makeWater(kind: .beer)
        advance(water, frames: 360)
        let initialFoam = water.foamLiquidArea
        try #require(initialFoam > 0)
        try #require(water.airborneFraction < 1e-9)

        // 実行
        advance(water, frames: 600)

        // 検証
        #expect(water.foamLiquidArea > 0)
        #expect(water.foamLiquidArea < initialFoam * 0.3)
    }

    @Test("ビールは注水終了から10秒で白濁度が5パーセント未満へ減る")
    func beerCloudinessFadesAfterPouring() throws {
        // 準備
        let water = makeWater(kind: .beer)
        advance(water, frames: 360)
        let initialCloudiness = water.beerCloudiness
        try #require(initialCloudiness > 0)
        try #require(water.airborneFraction < 1e-9)

        // 実行
        advance(water, frames: 600)

        // 検証
        #expect(water.beerCloudiness < initialCloudiness * 0.05)
    }

    @Test("ビールの泡が排液しても着水済みの液量と投入総量は変わらない")
    func beerDrainagePreservesLiquidVolume() throws {
        // 準備
        let water = makeWater(kind: .beer)
        advance(water, frames: 360)
        let initialLandedArea = water.landedArea
        try #require(water.foamLiquidArea > 0)
        try #require(water.airborneFraction < 1e-9)

        // 実行
        advance(water, frames: 600)

        // 検証
        #expect(abs(water.landedArea - initialLandedArea) < 1e-9)
        #expect(abs(water.fraction - 0.5) < 1e-9)
    }

    @Test("ビールをリセットすると表面の泡と液中の白濁を消す")
    func resetClearsBeerFoamAndCloudiness() throws {
        // 準備
        let water = makeWater(kind: .beer)
        advance(water, frames: 120)
        try #require(water.foamLiquidArea > 0)
        try #require(water.beerCloudiness > 0)

        // 実行
        water.reset(configuration: water.configuration, start: false)

        // 検証
        #expect(water.foamLiquidArea == 0)
        #expect(water.beerCloudiness == 0)
        #expect(water.foamHeight == 0)
    }

    @Test("ビール以外の種類には表面の泡や液中の白濁が生じない",
          arguments: [FluidKind.water, .sparklingWater, .viscousWater])
    func otherPresetsDoNotDevelopBeerFoam(kind: FluidKind) {
        // 準備
        let water = makeWater(kind: kind)

        // 実行
        advance(water, frames: 240)

        // 検証
        #expect(water.foamLiquidArea == 0)
        #expect(water.beerCloudiness == 0)
    }

    @Test("どの種類でも注水中の液量を保存し静止後は指定量が容器に残る",
          arguments: FluidKind.allCases, [0.0, 0.5, 1.0])
    func presetsPreserveRequestedVolume(kind: FluidKind, fill: Double) {
        // 準備
        let water = makeWater(kind: kind, fill: fill)
        var largestVolumeError = 0.0

        // 実行
        for _ in 0..<900 {
            water.advance(by: 1 / 60)
            let accountedFraction = water.jetFraction + water.splashFraction + water.landedFraction
            let error = abs(accountedFraction - water.fraction)
            largestVolumeError = error.isFinite ? max(largestVolumeError, error) : .infinity
        }

        // 検証
        #expect(largestVolumeError < 1e-9)
        #expect(abs(water.fraction - fill) < 1e-9)
        #expect(abs(water.landedFraction - fill) < 1e-8)
        #expect(abs(water.meanDepth / water.height - fill) < 1e-8)
    }

    @Test("どの種類と指定量でも注水から静止まで水深が有限で容器内に収まる",
          arguments: FluidKind.allCases, [0.0, 0.5, 1.0])
    func presetDepthsRemainFiniteAndInsideContainer(kind: FluidKind, fill: Double) {
        // 準備
        let water = makeWater(kind: kind, fill: fill)
        var depthsRemainValid = true

        // 実行
        for _ in 0..<900 {
            water.advance(by: 1 / 60)
            let currentDepthsAreValid = water.depths.allSatisfy {
                $0.isFinite && $0 >= 0 && $0 <= water.height + 1e-9
            }
            depthsRemainValid = currentDepthsAreValid && depthsRemainValid
        }

        // 検証
        #expect(depthsRemainValid)
    }

    @Test("どの種類と指定量でも気泡の同時数が上限を超えない",
          arguments: FluidKind.allCases, [0.0, 0.5, 1.0])
    func presetBubblesRemainWithinLimit(kind: FluidKind, fill: Double) {
        // 準備
        let water = makeWater(kind: kind, fill: fill)
        var largestBubbleCount = 0

        // 実行
        for _ in 0..<900 {
            water.advance(by: 1 / 60)
            largestBubbleCount = max(largestBubbleCount, water.bubbleCount)
        }

        // 検証
        #expect(largestBubbleCount <= WaterModel.maximumBubbles)
    }

    @Test("ビールと炭酸水は注水終了後も水量を変えず描画可能な気泡が上がる",
          arguments: [FluidKind.beer, .sparklingWater])
    func carbonatedPresetsKeepBubblingAfterPouring(kind: FluidKind) {
        // 準備
        let water = makeWater(kind: kind)

        // 実行
        advance(water, frames: 600)

        // 検証
        #expect(!water.isPouring)
        #expect(water.airborneFraction < 1e-9)
        #expect(water.bubbleCount > 0)
        #expect(abs(water.landedFraction - 0.5) < 1e-9)
        #expect(water.bubbleVertices().allSatisfy { $0.position.x.isFinite && $0.position.y.isFinite })
    }

    @Test("ビールと炭酸水を空にリセットすると気泡が消え再発生しない",
          arguments: [FluidKind.beer, .sparklingWater])
    func resettingCarbonatedPresetsStopsBubbles(kind: FluidKind) throws {
        // 準備
        let water = makeWater(kind: kind)
        advance(water, frames: 600)
        try #require(water.bubbleCount > 0)

        // 実行
        water.reset(configuration: water.configuration, start: false)
        advance(water, frames: 120)

        // 検証
        #expect(water.bubbleCount == 0)
    }

    @Test("注水後の炭酸気泡は固定の列に偏らず容器の幅に広がる",
          arguments: [FluidKind.beer, .sparklingWater])
    func carbonationSpreadsAcrossContainer(kind: FluidKind) throws {
        // 準備
        let water = makeWater(kind: kind)

        // 実行
        advance(water, frames: 600)
        let vertices = water.bubbleVertices()

        // 検証
        let centers = stride(from: 0, to: vertices.count, by: 6).map {
            (vertices[$0].position.x + vertices[$0 + 5].position.x) / 2
        }
        let minimum = try #require(centers.min())
        let maximum = try #require(centers.max())
        #expect(maximum - minimum > 0.5)
        #expect(centers.allSatisfy { $0 >= 0 && $0 <= 1 })
        #expect(Set(centers.map { Int($0 * 8) }).count >= 6)
    }

    @Test("同じ設定でリセットして注ぎ直すと炭酸気泡のばらつきを再現する",
          arguments: [FluidKind.beer, .sparklingWater])
    func carbonationRepeatsAfterReset(kind: FluidKind) throws {
        // 準備
        let water = makeWater(kind: kind)
        advance(water, frames: 600)
        let original = water.bubbleVertices()
        try #require(!original.isEmpty)

        // 実行
        water.reset(configuration: water.configuration, start: true)
        advance(water, frames: 600)
        let repeated = water.bubbleVertices()

        // 検証
        #expect(repeated.map(\.position) == original.map(\.position))
        #expect(repeated.map(\.appearance) == original.map(\.appearance))
    }

    @Test("粘度のある水は通常の水より着水後の波の運動エネルギーを抑える")
    func viscousPresetReducesWaves() throws {
        // 準備
        let water = makeWater(kind: .water)
        let viscous = makeWater(kind: .viscousWater)

        // 実行
        advance(water, frames: 240)
        advance(viscous, frames: 240)

        // 検証
        try #require(water.kineticEnergy > 0)
        #expect(viscous.kineticEnergy < water.kineticEnergy * 0.5)
    }

    @Test("粘度のある水は通常の水より着水時の飛沫量を抑える")
    func viscousPresetReducesSpray() throws {
        // 準備
        let water = makeWater(kind: .water)
        let viscous = makeWater(kind: .viscousWater)
        var waterSpray = 0.0
        var viscousSpray = 0.0

        // 実行
        for _ in 0..<240 {
            water.advance(by: 1 / 60)
            viscous.advance(by: 1 / 60)
            waterSpray = max(waterSpray, water.splashFraction)
            viscousSpray = max(viscousSpray, viscous.splashFraction)
        }

        // 検証
        try #require(waterSpray > 0)
        #expect(viscousSpray < waterSpray * 0.25)
    }

    @Test("粘度のある水は注ぎ終わりの帯を分離せず全量を容器に戻す")
    func viscousTailStaysConnected() {
        // 準備
        let water = makeWater(kind: .viscousWater)

        // 実行
        advance(water, frames: 600)

        // 検証
        #expect(water.separatedTailArea == 0)
        #expect(abs(water.landedFraction - 0.5) < 1e-9)
    }

    @Test("色の選択は投入量と水面と気泡の計算結果を変えない", arguments: FluidColorChoice.allCases)
    func colorsDoNotChangePhysics(color: FluidColorChoice) {
        // 準備
        let reference = makeWater(kind: .beer)
        let actual = makeWater(kind: .beer, color: color)

        // 実行
        advance(reference, frames: 120)
        advance(actual, frames: 120)

        // 検証
        #expect(actual.depths == reference.depths)
        #expect(actual.fraction == reference.fraction)
        #expect(actual.bubbleCount == reference.bubbleCount)
    }

    private func makeWater(kind: FluidKind, fill: Double = 0.5, color: FluidColorChoice = .standard) -> WaterModel {
        let water = WaterModel(aspectRatio: 2.16)
        var configuration = FluidConfiguration()
        configuration.kind = kind
        configuration.fill = fill
        configuration.flow = 0.16
        configuration.color = color
        water.reset(configuration: configuration, start: true)
        return water
    }

    private func advance(_ water: WaterModel, frames: Int) {
        for _ in 0..<frames {
            water.advance(by: 1 / 60)
        }
    }
}
