import Foundation
import SwiftUI
import Testing
import UIKit
@testable import LiquidAnimation

/// 画像・設定・ホストはケースごとに所有し、スコープ終了時に解放する。
@MainActor
struct LiquidFillRenderingTests {
    @Test("空の日付セルには液体を描かない")
    func emptyCalendarCellsContainNoLiquid() throws {
        // 準備
        let content = try calendarCells(progress: 0)

        // 実行
        let image = try render(content, name: "calendar-empty-cells")

        // 検証
        #expect(image.cyanPixelCount == 0)
        #expect(image.darkPixelCount > 100)
    }

    @Test("日付セルの投入率が上がると液体の描画面積が増える", arguments: [0.5, 1.0])
    func calendarProgressIncreasesLiquidArea(progress: Double) throws {
        // 準備
        let lowerProgress = try calendarCells(progress: progress / 2)
        let higherProgress = try calendarCells(progress: progress)

        // 実行
        let lowerImage = try render(lowerProgress, name: "calendar-lower-\(progress)")
        let higherImage = try render(higherProgress, name: "calendar-higher-\(progress)")

        // 検証
        #expect(lowerImage.cyanPixelCount > 0)
        #expect(higherImage.cyanPixelCount > lowerImage.cyanPixelCount * 3 / 2)
    }

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
            .environment(\.calendar, fixedCalendar())
            .environment(\.timeZone, fixedCalendar().timeZone))
        renderer.scale = 2
        return try RenderedTestImage(try #require(renderer.uiImage), name: name)
    }

    private func calendarCells(progress: Double) throws -> some View {
        let month = LiquidCalendarMonth(containing: try octoberFirst(), calendar: fixedCalendar())
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 8) {
            ForEach(month.days) { day in
                LiquidCalendarCell(day: day, progress: progress, color: .liquidFill(for: FluidConfiguration()))
            }
        }
        .padding(16).frame(width: 400)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func fixedCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private func octoberFirst() throws -> Date {
        try #require(fixedCalendar().date(from: DateComponents(year: 2026, month: 10, day: 1)))
    }
}
