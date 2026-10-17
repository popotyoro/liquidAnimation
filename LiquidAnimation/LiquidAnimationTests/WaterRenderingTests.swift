import CoreGraphics
import Foundation
import ImageIO
import Metal
import Testing
import UniformTypeIdentifiers
@testable import LiquidAnimation

@MainActor
struct WaterRenderingTests {
    @Test
    func continuousWaterRendersAtHalfHeightWithConfiguredOpacity() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let library = try #require(device.makeDefaultLibrary())
        let queue = try #require(device.makeCommandQueue())
        let fluid = try FluidSimulation(device: device, aspectRatio: 2.16)
        var config = FluidConfiguration()
        config.flow = 0.16
        fluid.model.reset(configuration: config, start: true)
        let width = 400, height = 864
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
            width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget]
        let target = try #require(device.makeTexture(descriptor: descriptor))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let started = Date()
        for frame in 1...480 {
            fluid.model.advance(by: 1 / 60)
            if ![8, 120, 195, 210, 480].contains(frame) { continue }
            if frame == 210 {
                #expect(!fluid.model.isPouring)
                #expect(!fluid.model.streamVertices().isEmpty)
                #expect(abs(fluid.model.fraction - config.fill) < 1e-9)
            }
            fluid.uploadSurface()
            let command = try #require(queue.makeCommandBuffer())
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
            let encoder = try #require(command.makeRenderCommandEncoder(descriptor: pass))
            var uniforms = WaterUniforms(viewport: SIMD4(Float(width), Float(height), 0.45,
                                                        Float(fluid.model.columnCount)))
            uniforms.detail = fluid.model.visualDetails
            if frame == 120 { #expect(fluid.model.bubbleCount > 0) }
            if frame == 480 { #expect(fluid.model.bubbleCount == 0) }
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<WaterUniforms>.stride, index: 0)
            for layer in 0...3 {
                let stream = layer == 0
                let bubble = layer == 2
                let spray = layer == 3
                if bubble && fluid.bubbleVertexCount == 0 { continue }
                if spray && fluid.splashVertexCount == 0 { continue }
                if stream && fluid.streamVertexCount == 0 { continue }
                let pipeline = MTLRenderPipelineDescriptor()
                pipeline.vertexFunction = library.makeFunction(name: bubble ? "bubbleVertex" : ((stream || spray) ? "streamVertex" : "waterVertex"))
                pipeline.fragmentFunction = library.makeFunction(name: bubble ? "bubbleFragment" : (spray ? "splashFragment" : (stream ? "streamFragment" : "waterFragment")))
                let color = pipeline.colorAttachments[0]!
                color.pixelFormat = .rgba8Unorm
                color.isBlendingEnabled = true
                color.sourceRGBBlendFactor = .one
                color.sourceAlphaBlendFactor = .one
                color.destinationRGBBlendFactor = .oneMinusSourceAlpha
                color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                encoder.setRenderPipelineState(try device.makeRenderPipelineState(descriptor: pipeline))
                if bubble {
                    encoder.setVertexBuffer(fluid.bubbleBuffer, offset: 0, index: 0)
                    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: fluid.bubbleVertexCount)
                } else if spray {
                    encoder.setVertexBuffer(fluid.splashBuffer, offset: 0, index: 0)
                    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: fluid.splashVertexCount)
                } else if stream {
                    encoder.setVertexBuffer(fluid.streamBuffer, offset: 0, index: 0)
                    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: fluid.streamVertexCount)
                } else {
                    encoder.setFragmentBuffer(fluid.surfaceBuffer, offset: 0, index: 1)
                    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                }
            }
            encoder.endEncoding()
            command.commit()
            command.waitUntilCompleted()
            #expect(command.status == .completed)
            target.getBytes(&pixels, bytesPerRow: width * 4,
                            from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            if frame == 480 {
                #expect(pixels[(height / 4 * width + width / 2) * 4 + 3] == 0)
                #expect(abs(Int(pixels[(height * 3 / 4 * width + width / 2) * 4 + 3]) - 115) <= 1)
            }
            let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
            let image = try #require(CGImage(width: width, height: height, bitsPerComponent: 8,
                bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent))
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("water-frame-\(frame).png")
            let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL,
                UTType.png.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, nil)
            #expect(CGImageDestinationFinalize(destination))
            print("Water render: \(url.path)")
        }
        print("Water model and offscreen rendering: \(Date().timeIntervalSince(started) / 480 * 1000) ms/frame (debug, includes five captures)")
    }
}
