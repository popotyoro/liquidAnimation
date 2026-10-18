import Metal
import QuartzCore
import Testing
@testable import LiquidAnimation

@MainActor
struct FluidPerformanceTests {
    @Test("水位が上がる各段階の計算・描画転送時間を記録できる",
          arguments: [FluidKind.water, .beer])
    func recordFramePreparationCost(kind: FluidKind) throws {
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
        for phase in 0..<3 {
            print("Frame preparation \(kind.rawValue) phase \(phase): physics \(physics[phase] / Double(counts[phase])) ms, upload \(upload[phase] / Double(counts[phase])) ms")
        }
        #expect(abs(simulation.model.fraction - 0.8) < 1e-9)
    }
}
