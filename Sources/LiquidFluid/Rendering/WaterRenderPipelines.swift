import Metal

/// alpha乗算済みの合成設定と描画順を一か所で管理する。オフスクリーン検証でも同じ経路を使う。
struct WaterRenderPipelines {
    private let surface: any MTLRenderPipelineState
    private let stream: any MTLRenderPipelineState
    private let splash: any MTLRenderPipelineState
    private let bubble: any MTLRenderPipelineState
    private let foam: any MTLRenderPipelineState
    private let surfacePreparation: any MTLComputePipelineState

    static func makeLibrary(device: any MTLDevice) throws -> any MTLLibrary {
        try device.makeDefaultLibrary(bundle: .module)
    }

    init(device: any MTLDevice, library: any MTLLibrary, pixelFormat: MTLPixelFormat) throws {
        func make(vertex: String, fragment: String) throws -> any MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: vertex)
            descriptor.fragmentFunction = library.makeFunction(name: fragment)
            let attachment = descriptor.colorAttachments[0]!
            attachment.pixelFormat = pixelFormat
            attachment.isBlendingEnabled = true
            attachment.sourceRGBBlendFactor = .one
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }
        surface = try make(vertex: "waterVertex", fragment: "waterFragment")
        stream = try make(vertex: "streamVertex", fragment: "streamFragment")
        splash = try make(vertex: "streamVertex", fragment: "splashFragment")
        bubble = try make(vertex: "bubbleVertex", fragment: "bubbleFragment")
        foam = try make(vertex: "waterVertex", fragment: "foamFragment")
        guard let prepare = library.makeFunction(name: "prepareWaterSurface") else {
            throw FluidError.unavailable("表示用水面の計算関数が見つかりませんでした。")
        }
        surfacePreparation = try device.makeComputePipelineState(function: prepare)
    }

    private func frameUniforms(_ simulation: FluidSimulation, uniforms: WaterUniforms) -> WaterUniforms {
        var uniforms = uniforms
        uniforms.foam.x = Float(simulation.model.foamHeight / simulation.model.width)
        uniforms.foam.y = Float(simulation.model.beerCloudiness)
        uniforms.foam.z = Float(simulation.model.meanDepth / simulation.model.height)
        uniforms.foam.w = min(uniforms.viewport.x, Float(FluidSimulation.maximumSurfaceSamples))
        return uniforms
    }

    /// 横位置だけで決まる水面と傾きを先に計算し、各描画パスで共有する。
    /// 同じコマンドバッファ内で描画より先に実行する。
    func prepareSurface(_ simulation: FluidSimulation, command: any MTLCommandBuffer,
                        uniforms: WaterUniforms) throws {
        guard let encoder = command.makeComputeCommandEncoder() else {
            throw FluidError.unavailable("表示用水面の計算コマンドを作成できませんでした。")
        }
        var uniforms = frameUniforms(simulation, uniforms: uniforms)
        encoder.setComputePipelineState(surfacePreparation)
        encoder.setBytes(&uniforms, length: MemoryLayout<WaterUniforms>.stride, index: 0)
        encoder.setBuffer(simulation.surfaceBuffer, offset: 0, index: 1)
        encoder.setBuffer(simulation.surfaceSamplesBuffer, offset: 0, index: 2)
        let count = max(1, Int(uniforms.foam.w))
        // 非一様なスレッドグループを要求しない。端数はkernelの範囲チェックで除く。
        let groupWidth = surfacePreparation.threadExecutionWidth
        let groups = (count + groupWidth - 1) / groupWidth
        encoder.dispatchThreadgroups(MTLSize(width: groups, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: groupWidth, height: 1, depth: 1))
        encoder.endEncoding()
    }

    func encode(_ simulation: FluidSimulation, with encoder: any MTLRenderCommandEncoder, uniforms: WaterUniforms) {
        var uniforms = frameUniforms(simulation, uniforms: uniforms)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<WaterUniforms>.stride, index: 0)
        // 水流 → 容器内の水 → 気泡 → 表面の泡 → 飛沫。
        drawVertices(simulation.streamBuffer, count: simulation.streamVertexCount,
                     primitive: .triangleStrip, pipeline: stream, encoder: encoder)
        encoder.setRenderPipelineState(surface)
        encoder.setFragmentBuffer(simulation.surfaceSamplesBuffer, offset: 0, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        drawVertices(simulation.bubbleBuffer, count: simulation.bubbleVertexCount,
                     primitive: .triangle, pipeline: bubble, encoder: encoder)
        drawFoam(simulation.model, encoder: encoder)
        drawVertices(simulation.splashBuffer, count: simulation.splashVertexCount,
                     primitive: .triangle, pipeline: splash, encoder: encoder)
    }

    private func drawFoam(_ model: WaterModel, encoder: any MTLRenderCommandEncoder) {
        guard model.foamHeight > 1e-7 else { return }
        encoder.setRenderPipelineState(foam)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    private func drawVertices(_ buffer: any MTLBuffer, count: Int, primitive: MTLPrimitiveType,
                              pipeline: any MTLRenderPipelineState, encoder: any MTLRenderCommandEncoder) {
        guard count > 0 else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: primitive, vertexStart: 0, vertexCount: count)
    }
}
