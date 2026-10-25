import Foundation
import SwiftUI
import Testing
import UIKit
import LiquidFluid
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
