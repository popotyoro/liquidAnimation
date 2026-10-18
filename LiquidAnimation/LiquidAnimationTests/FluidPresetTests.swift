import Testing
@testable import LiquidAnimation

@MainActor
struct FluidPresetTests {
    @Test("ビールは注水後に水量を保ったまま泡が減り液中の白濁が抜ける")
    func beerClearsAndDrainsWithoutLosingVolume() {
        let water = makeWater(kind: .beer)
        for _ in 0..<360 { water.advance(by: 1 / 60) }
        let foam = water.foamLiquidArea
        let cloudiness = water.beerCloudiness
        let landed = water.landedArea
        #expect(foam > 0)
        #expect(cloudiness > 0)
        #expect(water.airborneFraction < 1e-9)

        for _ in 0..<600 { water.advance(by: 1 / 60) }

        #expect(water.foamLiquidArea > 0)
        #expect(water.foamLiquidArea < foam * 0.3)
        #expect(water.beerCloudiness < cloudiness * 0.05)
        #expect(abs(water.landedArea - landed) < 1e-9)
        #expect(abs(water.fraction - 0.5) < 1e-9)
    }

    @Test("ビールをリセットすると泡と液中の白濁も消える")
    func resetClearsBeerFoamAndCloudiness() {
        let water = makeWater(kind: .beer)
        for _ in 0..<120 { water.advance(by: 1 / 60) }
        #expect(water.foamLiquidArea > 0)
        #expect(water.beerCloudiness > 0)

        water.reset(configuration: water.configuration, start: false)

        #expect(water.foamLiquidArea == 0)
        #expect(water.beerCloudiness == 0)
        #expect(water.foamHeight == 0)
    }

    @Test("ビール以外には表面の泡や液中の白濁を加えない",
          arguments: [FluidKind.water, .sparklingWater, .viscousWater])
    func otherPresetsDoNotDevelopBeerFoam(kind: FluidKind) {
        let water = makeWater(kind: kind)
        for _ in 0..<240 { water.advance(by: 1 / 60) }
        #expect(water.foamLiquidArea == 0)
        #expect(water.beerCloudiness == 0)
    }

    @Test("どの種類でも指定量を保存し水深を容器内に保つ",
          arguments: FluidKind.allCases, [0.0, 0.5, 1.0])
    func presetsPreserveRequestedVolume(kind: FluidKind, fill: Double) {
        let water = makeWater(kind: kind, fill: fill)
        for _ in 0..<900 {
            water.advance(by: 1 / 60)
            #expect(water.bubbleCount <= WaterModel.maximumBubbles)
            #expect(water.depths.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= water.height + 1e-9 })
            #expect(abs(water.jetFraction + water.splashFraction + water.landedFraction - water.fraction) < 1e-9)
        }
        #expect(abs(water.fraction - fill) < 1e-9)
        #expect(abs(water.landedFraction - fill) < 1e-8)
        #expect(abs(water.meanDepth / water.height - fill) < 1e-8)
    }

    @Test("ビールと炭酸水は注水終了後も水量を変えず気泡が上がる", arguments: [FluidKind.beer, .sparklingWater])
    func carbonatedPresetsKeepBubblingAfterPouring(kind: FluidKind) {
        let water = makeWater(kind: kind)
        for _ in 0..<600 { water.advance(by: 1 / 60) }

        #expect(!water.isPouring)
        #expect(water.airborneFraction < 1e-9)
        #expect(water.bubbleCount > 0)
        #expect(water.bubbleCount <= WaterModel.maximumBubbles)
        #expect(abs(water.landedFraction - 0.5) < 1e-9)
        #expect(water.bubbleVertices().allSatisfy { $0.position.x.isFinite && $0.position.y.isFinite })

        water.reset(configuration: water.configuration, start: false)
        for _ in 0..<120 { water.advance(by: 1 / 60) }
        #expect(water.bubbleCount == 0)
    }

    @Test("注水後の炭酸気泡は固定の列に偏らず容器の幅に広がる", arguments: [FluidKind.beer, .sparklingWater])
    func carbonationSpreadsAcrossContainer(kind: FluidKind) throws {
        let water = makeWater(kind: kind)
        for _ in 0..<600 { water.advance(by: 1 / 60) }

        let vertices = water.bubbleVertices()
        let centers = stride(from: 0, to: vertices.count, by: 6).map {
            (vertices[$0].position.x + vertices[$0 + 5].position.x) / 2
        }
        let minimum = try #require(centers.min())
        let maximum = try #require(centers.max())
        #expect(maximum - minimum > 0.5)
        #expect(centers.allSatisfy { $0 >= 0 && $0 <= 1 })
        // 幅を8区間に分け、以前の4列では満たせない広がりを確認する。
        #expect(Set(centers.map { Int($0 * 8) }).count >= 6)
    }

    @Test("同じ設定でリセットして注ぎ直すと炭酸気泡のばらつきを再現する", arguments: [FluidKind.beer, .sparklingWater])
    func carbonationRepeatsAfterReset(kind: FluidKind) {
        let water = makeWater(kind: kind)
        for _ in 0..<600 { water.advance(by: 1 / 60) }
        let original = water.bubbleVertices()
        #expect(!original.isEmpty)

        water.reset(configuration: water.configuration, start: true)
        for _ in 0..<600 { water.advance(by: 1 / 60) }
        let repeated = water.bubbleVertices()

        #expect(repeated.map(\.position) == original.map(\.position))
        #expect(repeated.map(\.appearance) == original.map(\.appearance))
    }

    @Test("粘度のある水は通常の水より着水後の波と飛沫を抑える")
    func viscousPresetReducesWavesAndSpray() {
        let water = makeWater(kind: .water)
        let viscous = makeWater(kind: .viscousWater)
        var waterSpray = 0.0
        var viscousSpray = 0.0
        for _ in 0..<240 {
            water.advance(by: 1 / 60)
            viscous.advance(by: 1 / 60)
            waterSpray = max(waterSpray, water.splashFraction)
            viscousSpray = max(viscousSpray, viscous.splashFraction)
        }

        #expect(water.kineticEnergy > 0)
        #expect(viscous.kineticEnergy < water.kineticEnergy * 0.5)
        #expect(waterSpray > 0)
        #expect(viscousSpray < waterSpray * 0.25)
    }

    @Test("粘度のある水は注ぎ終わりの帯を分離せず全量を容器に戻す")
    func viscousTailStaysConnected() {
        let water = makeWater(kind: .viscousWater)
        for _ in 0..<600 { water.advance(by: 1 / 60) }

        #expect(water.separatedTailArea == 0)
        #expect(abs(water.landedFraction - 0.5) < 1e-9)
    }

    @Test("色の選択は投入量と水面の計算結果を変えない", arguments: FluidColorChoice.allCases)
    func colorsDoNotChangePhysics(color: FluidColorChoice) {
        let reference = makeWater(kind: .beer)
        let actual = makeWater(kind: .beer, color: color)
        for _ in 0..<120 {
            reference.advance(by: 1 / 60)
            actual.advance(by: 1 / 60)
        }

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
}
