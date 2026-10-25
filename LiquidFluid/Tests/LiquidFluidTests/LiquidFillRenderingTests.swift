import Foundation
import SwiftUI
import Testing
import UIKit
@testable import LiquidFluid

@MainActor
struct LiquidFillRenderingTests {
    @Test("軽量版の水は標準色として青を使う")
    func waterUsesBlueFill() {
        // 準備
        var configuration = FluidConfiguration()
        configuration.kind = .water

        // 実行
        let color = Color.liquidFill(for: configuration).resolve(in: EnvironmentValues())

        // 検証
        #expect(color.blue > color.red)
    }

    @Test("軽量版のビールは標準色としてアンバーを使う")
    func beerUsesAmberFill() {
        // 準備
        var configuration = FluidConfiguration()
        configuration.kind = .beer

        // 実行
        let color = Color.liquidFill(for: configuration).resolve(in: EnvironmentValues())

        // 検証
        #expect(color.red > color.blue)
    }

    @Test("軽量版で明示した色は液体の種類を変えても維持される")
    func explicitFillColorSurvivesKindChange() {
        // 準備
        var configuration = FluidConfiguration()
        configuration.kind = .beer
        configuration.color = .green
        let before = Color.liquidFill(for: configuration).resolve(in: EnvironmentValues())

        // 実行
        configuration.kind = .water
        let after = Color.liquidFill(for: configuration).resolve(in: EnvironmentValues())

        // 検証
        #expect(after == before)
    }

    @Test("軽量版の不透明度をゼロにすると塗りが透明になる")
    func zeroOpacityHidesFill() {
        // 準備
        var configuration = FluidConfiguration()
        configuration.kind = .beer

        // 実行
        configuration.opacity = 0
        let color = Color.liquidFill(for: configuration).resolve(in: EnvironmentValues())

        // 検証
        #expect(color.opacity == 0)
    }

    @Test("軽量版modifierは指定した割合を下端から塗り背景の文字を残す",
          arguments: [0.25, 0.5, 1.0])
    func modifierFillsRequestedArea(fraction: Double) throws {
        // 準備
        let content = Text("液体越しの文字")
            .foregroundStyle(.black)
            .frame(width: 200, height: 100)
            .background(.white)
            .liquidFill(fraction: fraction)

        // 実行
        let image = try render(content, name: "modifier-fill-\(fraction)")

        // 検証
        let expectedPixels = Double(image.width * image.height) * fraction
        #expect(abs(Double(image.cyanPixelCount) - expectedPixels) < expectedPixels * 0.1)
        #expect(image.darkPixelCount > 20)
    }

    @Test("進行中の水面には凹凸が描画される", arguments: [0.15, 0.35, 0.7])
    func movingWaveRendersUnevenSurface(progress: Double) throws {
        // 準備
        let content = LiquidFillShape(fraction: 0.5, waveProgress: progress)
            .fill(Color.cyan.opacity(0.3))
            .frame(width: 280, height: 100)
            .background(.white)

        // 実行
        let image = try render(content, name: "wave-progress-\(progress)")

        // 検証
        #expect(image.cyanPixelCount > 10_000)
        #expect(image.surfaceHeightDifference >= 1)
    }

    @Test("波の終了後には平らな水面が描画される")
    func completedWaveRendersFlatSurface() throws {
        // 準備
        let content = LiquidFillShape(fraction: 0.5, waveProgress: 1)
            .fill(Color.cyan.opacity(0.3))
            .frame(width: 280, height: 100)
            .background(.white)

        // 実行
        let image = try render(content, name: "wave-completed")

        // 検証
        #expect(image.cyanPixelCount > 10_000)
        #expect(image.surfaceHeightDifference == 0)
    }

    private func render<Content: View>(_ content: Content, name: String) throws -> RenderedTestImage {
        let renderer = ImageRenderer(content: content
            .environment(\.colorScheme, .light)
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
            .environment(\.calendar, Calendar(identifier: .gregorian))
            .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!))
        renderer.scale = 2
        return try RenderedTestImage(try #require(renderer.uiImage), name: name)
    }

}
