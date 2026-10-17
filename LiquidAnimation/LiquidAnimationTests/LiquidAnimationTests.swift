import Foundation
import Testing
@testable import LiquidAnimation

@MainActor
struct LiquidAnimationTests {
    @Test(arguments: [0.0, 0.5, 1.0])
    func requestedVolumeRemainsExactAfterSettling(fill: Double) {
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

    @Test
    func jetAndPoolAccountForAllWaterWhilePouring() {
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

    @Test
    func impactWavesLoseEnergyAfterInflowStops() {
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

    @Test(arguments: [-65.0, 0.0, 65.0])
    func sprayReturnsToPoolWithoutAddingWater(angle: Double) {
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
        water.reset(configuration: config, start: true)
        for _ in 0..<240 {
            water.advance(by: 1 / 60)
            if water.splashCount > 0 { break }
        }
        #expect(water.splashCount > 0)
        water.reset(configuration: config, start: false)
        #expect(water.splashVertices().isEmpty)
        #expect(water.splashFraction == 0)
    }

    @Test
    func resetClearsPoolAndFallingStream() {
        let water = WaterModel(aspectRatio: 2.16)
        water.reset(configuration: FluidConfiguration(), start: true)
        for _ in 0..<90 { water.advance(by: 1 / 60) }
        #expect(water.hasWater)
        water.reset(configuration: FluidConfiguration(), start: false)
        #expect(water.fraction == 0)
        #expect(water.landedFraction == 0)
        #expect(water.meanDepth == 0)
        #expect(water.time == 0)
        #expect(water.streamVertices().isEmpty)
    }
}
