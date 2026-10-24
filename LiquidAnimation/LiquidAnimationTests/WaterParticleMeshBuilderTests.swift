import Foundation
import Testing
@testable import LiquidAnimation

/// 各ケースがメッシュ生成器と入力粒子を所有し、後始末はローカル値の破棄で完了する。
@MainActor
struct WaterParticleMeshBuilderTests {
    @Test("物理領域の左上は描画領域の左上へ対応する")
    func physicalTopLeftMapsToViewportTopLeft() {
        // 準備
        let builder = WaterParticleMeshBuilder(width: 0.75, height: 1.62)

        // 実行
        let position = builder.normalizedPosition(.zero)

        // 検証
        #expect(position == SIMD2(0, 1))
    }

    @Test("物理領域の右下は描画領域の右下へ対応する")
    func physicalBottomRightMapsToViewportBottomRight() {
        // 準備
        let builder = WaterParticleMeshBuilder(width: 0.75, height: 1.62)

        // 実行
        let position = builder.normalizedPosition(SIMD2(0.75, 1.62))

        // 検証
        #expect(position == SIMD2(1, 0))
    }

    @Test("炭酸の微小な気泡も画面幅の1.2パーセント以上の直径を持つ")
    func carbonationHasMinimumVisibleDiameter() throws {
        // 準備
        let builder = WaterParticleMeshBuilder(width: 0.75, height: 1.62)
        let bubble = carbonatedBubble()

        // 実行
        let vertices = builder.bubbleVertices([bubble])

        // 検証
        let minimum = try #require(vertices.map(\.position.x).min())
        let maximum = try #require(vertices.map(\.position.x).max())
        #expect(abs(maximum - minimum - 0.012) < 1e-6)
    }

    @Test("生後0.2秒の炭酸気泡は完全な濃さで炭酸の質感を描画する")
    func carbonatedBubbleHasVisibleCarbonatedAppearance() throws {
        // 準備
        let builder = WaterParticleMeshBuilder(width: 0.75, height: 1.62)
        let bubble = carbonatedBubble()

        // 実行
        let vertices = builder.bubbleVertices([bubble])

        // 検証
        try #require(!vertices.isEmpty)
        #expect(vertices.allSatisfy { $0.appearance.x == 1 && $0.appearance.y == 1 })
    }

    @Test("飛沫を速度方向へ伸ばしても楕円の面積を保存する", arguments: [0.0, 2.0, 5.0])
    func stretchedSplashPreservesArea(speed: Double) throws {
        // 準備
        let builder = WaterParticleMeshBuilder(width: 0.75, height: 1.62)
        let area = 0.0001
        let drop = WaterModel.Drop(position: SIMD2(0.375, 0.81), velocity: SIMD2(0, speed), area: area)

        // 実行
        let vertices = builder.splashVertices([drop])

        // 検証
        let left = try #require(vertices.map(\.position.x).min())
        let right = try #require(vertices.map(\.position.x).max())
        let bottom = try #require(vertices.map(\.position.y).min())
        let top = try #require(vertices.map(\.position.y).max())
        let ellipseArea = Double(right - left) * 0.75 * Double(top - bottom) * 1.62 * .pi / 4
        #expect(abs(ellipseArea - area) < 1e-8)
    }

    private func carbonatedBubble() -> WaterModel.Bubble {
        WaterModel.Bubble(position: SIMD2(0.375, 0.81), velocity: .zero,
                          radius: 0.0001, age: 0.2, lifetime: 2, phase: 0, isCarbonated: true)
    }
}
