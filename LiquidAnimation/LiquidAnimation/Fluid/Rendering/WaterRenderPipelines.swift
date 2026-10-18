import Metal

/// alpha乗算済みの合成設定と描画順を一か所で管理する。オフスクリーン検証でも同じ経路を使う。
struct WaterRenderPipelines {
    private let surface: any MTLRenderPipelineState
    private let stream: any MTLRenderPipelineState
    private let splash: any MTLRenderPipelineState
    private let bubble: any MTLRenderPipelineState
    private let foam: any MTLRenderPipelineState

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
    }

    func encode(_ simulation: FluidSimulation, with encoder: any MTLRenderCommandEncoder, uniforms: WaterUniforms) {
        var uniforms = uniforms
        uniforms.foam.x = Float(simulation.model.foamHeight / simulation.model.width)
        uniforms.foam.y = Float(simulation.model.beerCloudiness)
        uniforms.foam.z = Float(simulation.model.meanDepth / simulation.model.height)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<WaterUniforms>.stride, index: 0)
        // 水流 → 容器内の水 → 気泡 → 表面の泡 → 飛沫。
        drawVertices(simulation.streamBuffer, count: simulation.streamVertexCount,
                     primitive: .triangleStrip, pipeline: stream, encoder: encoder)
        encoder.setRenderPipelineState(surface)
        encoder.setFragmentBuffer(simulation.surfaceBuffer, offset: 0, index: 1)
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
