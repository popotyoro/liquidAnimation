import CoreGraphics
import SwiftUI
import Testing
@testable import LiquidFluid

/// 後始末はローカルな形状とPathの解放で完結する。
struct LiquidFillShapeTests {
    @Test("投入率ゼロの軽量版は何も塗らない")
    func zeroFractionIsEmpty() {
        // 準備
        let shape = LiquidFillShape(fraction: 0)
        let container = CGRect(x: 10, y: 20, width: 200, height: 100)

        // 実行
        let path = shape.path(in: container)

        // 検証
        #expect(path.isEmpty)
    }

    @Test("軽量版の水位は下端を固定して投入率に比例する", arguments: [0.25, 0.5, 1.0])
    func fractionDeterminesFillHeight(fraction: Double) {
        // 準備
        let shape = LiquidFillShape(fraction: fraction)
        let container = CGRect(x: 10, y: 20, width: 200, height: 100)

        // 実行
        let bounds = shape.path(in: container).boundingRect

        // 検証
        #expect(abs(bounds.height - 100 * fraction) < 1e-5)
        #expect(abs(bounds.maxY - container.maxY) < 1e-5)
        #expect(bounds.width == container.width)
    }

    @Test("非有限の投入率では軽量版を空として扱う", arguments: [Double.nan, .infinity, -.infinity])
    func nonFiniteFractionIsEmpty(fraction: Double) {
        // 準備
        let shape = LiquidFillShape(fraction: fraction)
        let container = CGRect(x: 0, y: 0, width: 200, height: 100)

        // 実行
        let path = shape.path(in: container)

        // 検証
        #expect(path.isEmpty)
    }

    @Test("軽量版の波は容器の上端と底を越えない",
          arguments: [0.001, 0.5, 0.999], [0.15, 0.4, 0.7])
    func wavesRemainInsideContainer(fraction: Double, progress: Double) {
        // 準備
        let shape = LiquidFillShape(fraction: fraction, waveProgress: progress)
        let container = CGRect(x: 10, y: 20, width: 200, height: 100)

        // 実行
        let bounds = shape.path(in: container).boundingRect

        // 検証。CGPathの境界計算の丸めだけを許容する。
        #expect(bounds.minY >= container.minY - 1e-5)
        #expect(abs(bounds.maxY - container.maxY) < 1e-5)
        #expect(bounds.width == container.width)
    }

    @Test("波の開始前と終了後は平らな水面になる", arguments: [0.0, 1.0])
    func waveEndpointsAreFlat(progress: Double) {
        // 準備
        let shape = LiquidFillShape(fraction: 0.5, waveProgress: progress)
        let container = CGRect(x: 10, y: 20, width: 200, height: 100)
        let expected = LiquidFillShape(fraction: 0.5).path(in: container)

        // 実行
        let path = shape.path(in: container)

        // 検証
        #expect(path == expected)
    }

    @Test("満水の軽量版は波の途中でも容器全体を塗る", arguments: [0.15, 0.4, 0.7])
    func fullContainerHasNoWave(progress: Double) {
        // 準備
        let shape = LiquidFillShape(fraction: 1, waveProgress: progress)
        let container = CGRect(x: 10, y: 20, width: 200, height: 100)

        // 実行
        let path = shape.path(in: container)

        // 検証
        #expect(path == LiquidFillShape(fraction: 1).path(in: container))
    }

    @Test("空の軽量版は波の途中でも何も塗らない", arguments: [0.15, 0.4, 0.7])
    func emptyContainerHasNoWave(progress: Double) {
        // 準備
        let shape = LiquidFillShape(fraction: 0, waveProgress: progress)
        let container = CGRect(x: 10, y: 20, width: 200, height: 100)

        // 実行
        let path = shape.path(in: container)

        // 検証
        #expect(path.isEmpty)
    }

    @Test("軽量版の波は描画面積を変えず平均水位を保つ")
    func wavePreservesFilledArea() {
        // 準備
        let shape = LiquidFillShape(fraction: 0.5, waveProgress: 0.25)
        let container = CGRect(x: 0, y: 0, width: 200, height: 100)

        // 実行
        let path = shape.path(in: container)
        let filledSamples = (0..<200).reduce(0) { count, x in
            count + (0..<100).filter { y in
                path.contains(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5))
            }.count
        }

        // 検証。1px刻みの面積サンプリングによる誤差を許容する。
        #expect(abs(filledSamples - 10_000) < 40)
    }

    @Test("軽量版の波は終了が近づくと振幅が小さくなる")
    func waveAmplitudeDecays() {
        // 準備
        let container = CGRect(x: 0, y: 0, width: 200, height: 100)
        let early = LiquidFillShape(fraction: 0.5, waveProgress: 0.25)
        let late = LiquidFillShape(fraction: 0.5, waveProgress: 0.9)

        // 実行
        let earlyHeight = early.path(in: container).boundingRect.minY
        let lateHeight = late.path(in: container).boundingRect.minY

        // 検証
        #expect(earlyHeight < 49)
        #expect(lateHeight > earlyHeight)
    }
}
