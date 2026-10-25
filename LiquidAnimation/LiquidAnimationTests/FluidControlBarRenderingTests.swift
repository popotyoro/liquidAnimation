import SwiftUI
import Testing
import UIKit
@testable import LiquidFluid
@testable import LiquidAnimation

/// 後始末はテスト所有の設定・描画器・画像の解放で完結する。
@MainActor
struct FluidControlBarRenderingTests {
    @Test("通常文字と拡大文字の注水バーに最新の計測値が反映される",
          arguments: [DynamicTypeSize.large, .xxxLarge])
    func metricsChangesAreRendered(textSize: DynamicTypeSize) throws {
        // 準備
        let controls = FluidControls()
        controls.insertedFraction = 0.5
        let before = try render(controls: controls, textSize: textSize, name: "controls-before-\(textSize)")

        // 実行
        controls.framesPerSecond = 60
        controls.gpuMilliseconds = 1.2
        controls.simulationMilliseconds = 3.4
        let after = try render(controls: controls, textSize: textSize, name: "controls-after-\(textSize)")

        // 検証
        #expect(after.darkPixelCount > 100)
        #expect(try after.differingPixelCount(from: before) > 20)
    }

    private func render(controls: FluidControls, textSize: DynamicTypeSize,
                        name: String) throws -> RenderedTestImage {
        let content = FluidControlBar(controls: controls, openSettings: {})
            .frame(width: 360)
            .padding(16)
            .background(Color(uiColor: .systemGroupedBackground))
            .environment(\.dynamicTypeSize, textSize)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        return try RenderedTestImage(try #require(renderer.uiImage), name: name)
    }
}
