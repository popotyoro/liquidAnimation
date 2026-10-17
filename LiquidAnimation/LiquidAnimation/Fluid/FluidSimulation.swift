import Foundation
import Metal
import simd

// Kept in the same order and alignment as Fluid.metal. Positions are in grid-cell units.
struct FluidParticle {
    var position: SIMD2<Float>
    var velocity: SIMD2<Float>
    var affineX: SIMD2<Float>
    var affineY: SIMD2<Float>
}

struct FluidUniforms {
    var dimensions: SIMD4<UInt32>  // nx, ny, active count, first new particle
    var step: SIMD4<Float>        // dt, gravity, angle (radians), nozzle x
    var source: SIMD4<Float>      // speed, width, opacity, unused
}

enum FluidError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message): message
        }
    }
}

@MainActor
final class FluidSimulation {
    let device: any MTLDevice
    let nx: Int
    let ny: Int
    let capacity: Int
    let particles: any MTLBuffer
    let bins: any MTLBuffer
    let counts: any MTLBuffer
    let u: any MTLBuffer
    let v: any MTLBuffer
    let divergence: any MTLBuffer
    let pressureA: any MTLBuffer
    let pressureB: any MTLBuffer
    let surface: any MTLTexture
    let diagnostics: any MTLBuffer
    private let pipelines: [String: any MTLComputePipelineState]

    private(set) var particleCount = 0
    private(set) var targetCount = 0
    private(set) var configuration = FluidConfiguration()
    private(set) var elapsedTime: Float = 0
    private var emissionRemainder = 0.0
    private(set) var uniforms: FluidUniforms

    var isPouring: Bool { particleCount < targetCount }
    var fraction: Double { Double(particleCount) / Double(capacity) }

    init(device: any MTLDevice, library: any MTLLibrary, aspectRatio: Double,
         gridWidth: Int = 64) throws {
        self.device = device
        nx = gridWidth
        ny = min(256, max(32, Int((Double(gridWidth) * aspectRatio).rounded())))
        capacity = Int((Double(nx) - 0.4) * (Double(ny) - 0.4) * 4)
        let cells = nx * ny
        func buffer(_ length: Int, _ label: String) throws -> any MTLBuffer {
            guard let result = device.makeBuffer(length: length, options: .storageModeShared) else {
                throw FluidError.unavailable("計算用メモリを確保できませんでした。")
            }
            result.label = label
            memset(result.contents(), 0, length)
            return result
        }
        particles = try buffer(capacity * MemoryLayout<FluidParticle>.stride, "Fluid particles")
        counts = try buffer(cells * 4, "Cell particle counts")
        bins = try buffer(cells * 32 * 4, "Cell particle indices")
        u = try buffer((nx + 1) * ny * 4, "MAC horizontal velocity")
        v = try buffer(nx * (ny + 1) * 4, "MAC vertical velocity")
        divergence = try buffer(cells * 4, "Velocity divergence")
        pressureA = try buffer(cells * 4, "Pressure A")
        pressureB = try buffer(cells * 4, "Pressure B")
        diagnostics = try buffer(4, "Spatial bin overflow count")
        let texture = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r16Float, width: nx * 3, height: ny * 3, mipmapped: false)
        texture.usage = [.shaderRead, .shaderWrite]
        guard let surface = device.makeTexture(descriptor: texture) else {
            throw FluidError.unavailable("液面描画用のテクスチャを作成できませんでした。")
        }
        self.surface = surface
        var states: [String: any MTLComputePipelineState] = [:]
        for name in ["clearGrid", "spawnParticles", "binParticles", "particlesToGrid",
                     "computeDivergence", "solvePressure", "projectVelocity", "advectParticles",
                     "buildSurface"] {
            guard let function = library.makeFunction(name: name) else {
                throw FluidError.unavailable("Metal 関数 \(name) が見つかりません。")
            }
            states[name] = try device.makeComputePipelineState(function: function)
        }
        pipelines = states
        uniforms = FluidUniforms(dimensions: SIMD4(UInt32(nx), UInt32(ny), 0, 0),
                                 step: .zero, source: .zero)
    }

    func reset(configuration: FluidConfiguration, start: Bool) {
        self.configuration = configuration.sanitized
        particleCount = 0
        targetCount = start ? Int((Double(capacity) * self.configuration.fill).rounded()) : 0
        emissionRemainder = 0
        elapsedTime = 0
        memset(pressureA.contents(), 0, pressureA.length)
        memset(pressureB.contents(), 0, pressureB.length)
    }

    /// The caller serializes command buffers. Eight fixed substeps bound advection at 60 Hz.
    func encodeFrame(commandBuffer: any MTLCommandBuffer, deltaTime: Float,
                     opacity: Double, advance: Bool = true, pressureIterations: Int = 40) throws {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw FluidError.unavailable("Metal の計算コマンドを作成できませんでした。")
        }
        defer { encoder.endEncoding() }
        encoder.label = "APIC fluid simulation"
        let duration = min(max(deltaTime, 0), 1 / 60)
        let steps = advance ? 8 : 0
        let dt = duration / 8
        let speed = Float(nx) * 1.4
        // A 0.75 m wide container maps SI gravity to cells per second squared.
        let gravity = 9.81 * Float(nx) / 0.75
        let nozzleWidth = max(1.5, Float(capacity) * Float(configuration.flow) / (4 * speed))

        func bind(_ input: any MTLBuffer, _ output: any MTLBuffer) {
            for (index, buffer) in [particles, counts, bins, u, v, input, output,
                                    divergence].enumerated() {
                encoder.setBuffer(buffer, offset: 0, index: index)
            }
            encoder.setBuffer(diagnostics, offset: 0, index: 9)
            encoder.setTexture(surface, index: 0)
            encoder.setBytes(&uniforms, length: MemoryLayout<FluidUniforms>.stride, index: 8)
        }
        func dispatch(_ name: String, _ count: Int) {
            guard count > 0, let pipeline = pipelines[name] else { return }
            encoder.setComputePipelineState(pipeline)
            // Uniform groups also work on simulator GPUs without nonuniform dispatch support.
            // Every kernel guards its logical range, including the padded final group.
            let groupWidth = min(pipeline.threadExecutionWidth * 4, pipeline.maxTotalThreadsPerThreadgroup)
            let groupCount = (count + groupWidth - 1) / groupWidth
            encoder.dispatchThreadgroups(MTLSize(width: groupCount, height: 1, depth: 1),
                                         threadsPerThreadgroup: MTLSize(
                                            width: groupWidth, height: 1, depth: 1))
        }

        for _ in 0..<steps {
            let firstNew = particleCount
            if isPouring {
                emissionRemainder += Double(capacity) * configuration.flow * Double(dt)
                let add = min(targetCount - particleCount, Int(emissionRemainder))
                particleCount += add
                emissionRemainder -= Double(add)
            }
            uniforms = FluidUniforms(
                dimensions: SIMD4(UInt32(nx), UInt32(ny), UInt32(particleCount), UInt32(firstNew)),
                step: SIMD4(dt, gravity, Float(configuration.angle * .pi / 180),
                            Float(configuration.sourcePosition) * Float(nx)),
                source: SIMD4(speed, nozzleWidth, Float(opacity), 0))
            bind(pressureA, pressureB)
            dispatch("clearGrid", nx * ny)
            dispatch("spawnParticles", particleCount - firstNew)
            dispatch("binParticles", particleCount)
            dispatch("particlesToGrid", max((nx + 1) * ny, nx * (ny + 1)))
            dispatch("computeDivergence", nx * ny)
            var input = pressureA
            var output = pressureB
            for _ in 0..<pressureIterations {
                bind(input, output)
                dispatch("solvePressure", nx * ny)
                swap(&input, &output)
            }
            bind(input, output)
            dispatch("projectVelocity", max((nx + 1) * ny, nx * (ny + 1)))
            dispatch("advectParticles", particleCount)
            elapsedTime += dt
        }
        // Rebuild spatial bins after advection, including when a cleared/paused frame is drawn.
        uniforms.dimensions.z = UInt32(particleCount)
        uniforms.source.z = Float(opacity)
        bind(pressureA, pressureB)
        dispatch("clearGrid", nx * ny)
        dispatch("binParticles", particleCount)
        dispatch("buildSurface", surface.width * surface.height)
    }
}
