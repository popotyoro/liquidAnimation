import Foundation
import Testing
@testable import LiquidAnimation

@MainActor
struct WaterParticleMeshBuilderTests {
    let builder = WaterParticleMeshBuilder(width: 0.75, height: 1.62)

    @Test("物理領域の左上と右下を上下反転した正規化座標へ変換する")
    func physicalCoordinatesMapToViewport() {
        #expect(builder.normalizedPosition(.zero) == SIMD2(0, 1))
        #expect(builder.normalizedPosition(SIMD2(0.75, 1.62)) == SIMD2(1, 0))
    }

    @Test("炭酸の微小な気泡も画面幅の1.2パーセント以上の直径を持つ")
    func carbonationHasMinimumVisibleDiameter() throws {
        let bubble = WaterModel.Bubble(position: SIMD2(0.375, 0.81), velocity: .zero,
            radius: 0.0001, age: 0.2, lifetime: 2, phase: 0, isCarbonated: true)
        let vertices = builder.bubbleVertices([bubble])
        let minimum = try #require(vertices.map(\.position.x).min())
        let maximum = try #require(vertices.map(\.position.x).max())
        #expect(abs(maximum - minimum - 0.012) < 1e-6)
        #expect(vertices.allSatisfy { $0.appearance.x == 1 && $0.appearance.y == 1 })
    }

    @Test("飛沫を速度方向へ伸ばしても楕円の面積を保存する", arguments: [0.0, 2.0, 5.0])
    func stretchedSplashPreservesArea(speed: Double) throws {
        let area = 0.0001
        let drop = WaterModel.Drop(position: SIMD2(0.375, 0.81), velocity: SIMD2(0, speed), area: area)
        let vertices = builder.splashVertices([drop])
        let left = try #require(vertices.map(\.position.x).min())
        let right = try #require(vertices.map(\.position.x).max())
        let bottom = try #require(vertices.map(\.position.y).min())
        let top = try #require(vertices.map(\.position.y).max())
        let ellipseArea = Double(right - left) * 0.75 * Double(top - bottom) * 1.62 * .pi / 4
        #expect(abs(ellipseArea - area) < 1e-8)
    }
}
