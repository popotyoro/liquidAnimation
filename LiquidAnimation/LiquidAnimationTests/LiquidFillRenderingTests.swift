import Foundation
import Observation
import SwiftUI
import Testing
import UIKit
@testable import LiquidAnimation

@MainActor
@Suite(.serialized)
struct LiquidFillRenderingTests {
    @Test("日付セルは空・途中・完了でそれぞれの量まで下から塗られる")
    func calendarCellsRenderAtDifferentLevels() throws {
        let calendar = Calendar(identifier: .gregorian)
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 1)))
        let month = LiquidCalendarMonth(containing: date, calendar: calendar)
        for (index, progress) in [0.0, 0.5, 1.0].enumerated() {
            let content = LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7),
                                    spacing: 8) {
                ForEach(month.days) { day in
                    LiquidCalendarCell(day: day, progress: progress,
                                       color: .liquidFill(for: FluidConfiguration()))
                }
            }
            .padding(16).frame(width: 400)
            .background(Color(uiColor: .systemGroupedBackground))
            .environment(\.colorScheme, .light)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            let image = try #require(renderer.uiImage)
            try save(image, name: "liquid-calendar-phase-\(index)")
        }
    }

    @Test("実際の月間カレンダーでも空と投入後の水位が表示される")
    func calendarScreenRemainsVisible() async throws {
        for initiallyFilled in [false, true] {
            try await captureCalendar(initiallyFilled: initiallyFilled)
        }
        let beer = FluidControls()
        beer.configuration.kind = .beer
        try await capture(LiquidFillDemoView(controls: beer, openSettings: {}, initiallyFilled: true),
                          name: "liquid-calendar-beer")
        beer.configuration.color = .green
        try await capture(LiquidFillDemoView(controls: beer, openSettings: {}, initiallyFilled: true),
                          name: "liquid-calendar-green-beer")
    }

    private func captureCalendar(initiallyFilled: Bool) async throws {
        try await capture(LiquidFillDemoView(controls: FluidControls(), openSettings: {},
                                             initiallyFilled: initiallyFilled),
                          name: initiallyFilled ? "liquid-calendar-full" : "liquid-calendar-empty")
    }

    @Test("注ぐ・カレンダーの各Tabで画面とTabバーが表示される")
    func tabsShowEachDemo() async throws {
        for tab in [LiquidDemoTab.pour, .fill] {
            try await capture(ContentView(initialTab: tab), name: tab == .pour ? "liquid-tab-pour" : "liquid-tab-fill")
        }
    }

    @Test("ビールの標準色はアンバーになり明示色と不透明度は種類にかかわらず優先される")
    func fillColorUsesSharedConfiguration() {
        var config = FluidConfiguration()
        let environment = EnvironmentValues()
        let water = Color.liquidFill(for: config).resolve(in: environment)
        config.kind = .beer
        let beer = Color.liquidFill(for: config).resolve(in: environment)
        #expect(water.blue > water.red)
        #expect(beer.red > beer.blue)
        config.color = .green
        let greenBeer = Color.liquidFill(for: config).resolve(in: environment)
        config.kind = .water
        let greenWater = Color.liquidFill(for: config).resolve(in: environment)
        #expect(greenBeer == greenWater)
        config.opacity = 0
        #expect(Color.liquidFill(for: config).resolve(in: environment).opacity == 0)
    }

    private func capture<Content: View>(_ content: Content, name: String) async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let controller = UIHostingController(rootView: content.environment(\.colorScheme, .light))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            previousKeyWindow?.makeKey()
        }
        // 実際のカレンダーをレイアウト・描画させてから採取する。ImageRendererだけでは検証しない。
        try await Task.sleep(for: .milliseconds(500))
        controller.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try save(image, name: name)
        #expect(image.size.width > 0 && image.size.height > 0)
    }

    @Test("割合は行の高さに対応し0パーセントは何も塗らない", arguments: [0.0, 0.25, 0.5, 1.0])
    func fillHeightMatchesFraction(fraction: Double) {
        let path = LiquidFillShape(fraction: fraction).path(in: CGRect(x: 10, y: 20, width: 200, height: 100))
        if fraction == 0 {
            #expect(path.isEmpty)
        } else {
            #expect(abs(path.boundingRect.height - 100 * fraction) < 1e-8)
            #expect(path.boundingRect.maxY == 120)
            #expect(path.boundingRect.width == 200)
        }
    }

    @Test("非有限の割合は空として描画する", arguments: [Double.nan, .infinity, -.infinity])
    func nonFiniteFractionsRemainEmpty(fraction: Double) {
        #expect(LiquidFillShape(fraction: fraction).path(in: CGRect(x: 0, y: 0, width: 200, height: 100)).isEmpty)
    }

    @Test("軽量版の波は空と満水の境界を越えず最後は平らになる",
          arguments: [0.0, 0.001, 0.5, 0.999, 1.0])
    func wavesRemainInsideContainer(fraction: Double) {
        let rect = CGRect(x: 10, y: 20, width: 200, height: 100)
        let flat = LiquidFillShape(fraction: fraction).path(in: rect)
        for progress in [0.0, 0.15, 0.4, 0.7, 1.0] {
            let path = LiquidFillShape(fraction: fraction, waveProgress: progress).path(in: rect)
            if fraction == 0 {
                #expect(path.isEmpty)
            } else {
                #expect(path.boundingRect.minY >= rect.minY - 1e-8)
                // CGPathの境界計算で生じる浮動小数点の丸めを許容する。
                #expect(abs(path.boundingRect.maxY - rect.maxY) < 1e-5)
                #expect(path.boundingRect.width == rect.width)
            }
            if progress == 0 || progress == 1 || fraction == 1 {
                #expect(path == flat)
            }
        }
    }

    @Test("軽量版の波は平均水位を保ち減衰する")
    func wavesPreserveAverageLevelAndSettle() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let early = LiquidFillShape(fraction: 0.5, waveProgress: 0.25).path(in: rect)
        let late = LiquidFillShape(fraction: 0.5, waveProgress: 0.9).path(in: rect)
        #expect(early.boundingRect.minY < 49)
        #expect(late.boundingRect.minY > early.boundingRect.minY)
        // 実際に塗られる領域を積算し、水位50%の面積を保つことを確認する。
        var filledSamples = 0
        for x in 0..<200 {
            for y in 0..<100 {
                if early.contains(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)) {
                    filledSamples += 1
                }
            }
        }
        #expect(abs(filledSamples - 10_000) < 40)
    }

    @Test("軽量版の本番modifierで上昇から静止までの画像を出力する")
    func waveAnimationRendersOverTime() async throws {
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.keyWindow
        let state = WaveRenderingState()
        let window = UIWindow(windowScene: scene)
        let controller = UIHostingController(rootView: WaveRenderingView(state: state)
            .environment(\.colorScheme, .light))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            previousKeyWindow?.makeKey()
        }
        try await Task.sleep(for: .milliseconds(100))
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 1.8)) {
            state.fraction = 0.5
        }
        var previousTime = 0.0
        for time in [0.0, 0.4, 0.9, 1.8, 2.2, 2.8] {
            try await Task.sleep(for: .seconds(time - previousTime))
            previousTime = time
            controller.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            try save(image, name: "liquid-fill-wave-reduced-\(reduceMotion)-\(time)s")
        }
    }

    @Observable
    final class WaveRenderingState {
        var fraction = 0.0
    }

    private struct WaveRenderingView: View {
        let state: WaveRenderingState

        var body: some View {
            VStack(spacing: 24) {
                ForEach([0.2, 0.6, 1.0], id: \.self) { multiplier in
                    Text("軽量版の水面")
                        .frame(width: 280, height: 100)
                        .background(.white)
                        .liquidFill(fraction: state.fraction * multiplier)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.gray.opacity(0.15))
        }
    }

    private func save(_ image: UIImage, name: String) throws {
        let path = URL.temporaryDirectory.appendingPathComponent("\(name).png")
        try #require(image.pngData()).write(to: path)
        print("Liquid fill render: \(path.path)")
    }
}
