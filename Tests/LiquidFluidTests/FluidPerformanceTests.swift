import Metal
import QuartzCore
import Testing
@testable import LiquidFluid

@MainActor
struct FluidPerformanceTests {
    @Test("注水中と注水後の各60フレームで計算と描画転送の所要時間を記録する",
          arguments: [FluidKind.water, .beer])
    func recordFramePreparationCost(kind: FluidKind) throws {
        // 準備: モデル・共有バッファはこのケースだけが所有する。
        let device = try #require(MTLCreateSystemDefaultDevice())
        let simulation = try FluidSimulation(device: device, aspectRatio: 2.16)
        var configuration = FluidConfiguration()
        configuration.kind = kind
        configuration.fill = 0.8
        configuration.flow = 0.16
        simulation.model.reset(configuration: configuration, start: true)
        var physics = [Double](repeating: 0, count: 3)
        var upload = physics
        var counts = [Int](repeating: 0, count: 3)

        // 実行
        for frame in 1...420 {
            let start = CACurrentMediaTime()
            simulation.model.advance(by: 1 / 60)
            let updated = CACurrentMediaTime()
            simulation.uploadSurface()
            let end = CACurrentMediaTime()
            let phase: Int?
            switch frame {
            case 61...120: phase = 0
            case 181...240: phase = 1
            case 361...420: phase = 2
            default: phase = nil
            }
            if let phase {
                physics[phase] += (updated - start) * 1_000
                upload[phase] += (end - updated) * 1_000
                counts[phase] += 1
            }
        }
        // 検証: 速度の合否基準にはせず、必要な区間の有効な計測値を得られたことを確かめる。
        for phase in 0..<3 {
            #expect(counts[phase] == 60)
            #expect(physics[phase].isFinite && physics[phase] >= 0)
            #expect(upload[phase].isFinite && upload[phase] >= 0)
        }
        let report = (0..<3).map { phase in
            "Frame preparation \(kind.rawValue) phase \(phase): physics \(physics[phase] / Double(counts[phase])) ms, upload \(upload[phase] / Double(counts[phase])) ms"
        }.joined(separator: "\n")
        Attachment.record(report, named: "frame-preparation-\(kind.rawValue).txt")
        // 後始末: GPUへコマンドを発行していないため、ローカル資源はARCで解放される。
    }
}
