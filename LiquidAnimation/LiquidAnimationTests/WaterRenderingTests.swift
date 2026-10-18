import CoreGraphics
import Foundation
import ImageIO
import Metal
import Testing
import UniformTypeIdentifiers
@testable import LiquidAnimation

@MainActor
struct WaterRenderingTests {
    @Test("50%まで溜まった水は画面上部を透明に保ち指定した不透明度で描く", arguments: [0.0, 0.45, 1.0])
    func settledPoolUsesConfiguredOpacity(opacity: Double) throws {
        let scene = try OffscreenWater()
        scene.advance(frames: 480)

        let image = try scene.render(opacity: opacity)

        #expect(image.alpha(x: image.width / 2, y: image.height / 4) == 0)
        #expect(abs(Int(image.alpha(x: image.width / 2, y: image.height * 3 / 4)) - Int((opacity * 255).rounded())) <= 1)
        if opacity == 0.45 { try image.save(frame: 480) }
    }

    @Test("静止した水面は壁際だけ少し持ち上がり中央はほぼ50%に保つ")
    func settledPoolRisesSlightlyAtWalls() throws {
        let scene = try OffscreenWater()
        scene.advance(frames: 480)

        let image = try scene.render()
        let aboveSurface = image.height / 2 - 2

        #expect(image.alpha(x: 2, y: aboveSurface) > 100)
        #expect(image.alpha(x: image.width - 3, y: aboveSurface) > 100)
        #expect(image.alpha(x: image.width / 2, y: aboveSurface) == 0)
    }

    @Test("空の容器には液体を描かない")
    func emptyContainerRendersNothing() throws {
        let scene = try OffscreenWater(fill: 0)
        scene.advance(frames: 60)

        let image = try scene.render()

        #expect(image.pixels.allSatisfy { $0 == 0 })
    }

    @Test("不透明度0では注水中の水流・水面・飛沫・気泡を描かない")
    func zeroOpacityHidesEveryWaterLayer() throws {
        let scene = try OffscreenWater()
        scene.advance(frames: 120)
        #expect(scene.fluid.model.bubbleCount > 0)
        #expect(scene.fluid.model.splashCount > 0)

        let image = try scene.render(opacity: 0)

        #expect(image.pixels.allSatisfy { $0 == 0 })
    }

    @Test("注水開始と減流中も水流が描画される", arguments: [8, 195])
    func rampingJetRemainsVisible(frame: Int) throws {
        let scene = try OffscreenWater()
        scene.advance(frames: frame)

        let image = try scene.render()

        #expect(scene.fluid.streamVertexCount > 0)
        #expect(image.pixels.enumerated().contains { $0.offset % 4 == 3 && $0.element > 0 })
        try image.save(frame: frame)
    }

    @Test("注水中は気泡の描画データがあり静止後にはなくなる")
    func entrainedBubblesDisappearAfterPouring() throws {
        let scene = try OffscreenWater()
        scene.advance(frames: 120)
        let pouring = try scene.render()
        #expect(scene.fluid.bubbleVertexCount > 0)
        try pouring.save(frame: 120)

        scene.advance(frames: 360)
        _ = try scene.render()

        #expect(scene.fluid.bubbleVertexCount == 0)
    }

    @Test("入口を止めても未着水の水流は描画される")
    func stoppedInletKeepsFallingWaterVisible() throws {
        let scene = try OffscreenWater()
        scene.advance(frames: 210)

        let image = try scene.render()

        #expect(!scene.fluid.model.isPouring)
        #expect(abs(scene.fluid.model.fraction - 0.5) < 1e-9)
        #expect(scene.fluid.streamVertexCount > 0)
        try image.save(frame: 210)
    }

    @Test("分離した水流の末尾は容器へ戻るまで水滴の描画対象になる")
    func separatedTailRendersAsDrops() throws {
        let scene = try OffscreenWater()
        scene.advance(frames: 214)

        let image = try scene.render()

        #expect(scene.fluid.model.detachedDropCount > 0)
        #expect(scene.fluid.splashVertexCount > 0)
        try image.save(frame: 214)
    }

    @Test("どの種類も水面・水流・気泡をMetalで描画できる", arguments: FluidKind.allCases)
    func everyPresetRenders(kind: FluidKind) throws {
        let scene = try OffscreenWater(kind: kind)
        scene.advance(frames: 120)

        let image = try scene.render()

        #expect(image.alpha(x: image.width / 2, y: image.height - 10) > 0)
        try image.save(frame: 120, prefix: kind.rawValue)
    }

    @Test("どの種類も不透明度0では全描画パスが透明になる", arguments: FluidKind.allCases)
    func everyPresetSupportsZeroOpacity(kind: FluidKind) throws {
        let scene = try OffscreenWater(kind: kind)
        scene.advance(frames: 120)

        let image = try scene.render(opacity: 0)

        #expect(image.pixels.allSatisfy { $0 == 0 })
    }

    @Test("注水し直さず色だけを変えると形と不透明度を保って色が変わる")
    func colorChangesWithoutRestarting() throws {
        let scene = try OffscreenWater()
        scene.advance(frames: 480)
        let time = scene.fluid.model.time
        let fraction = scene.fluid.model.fraction
        let before = try scene.render(color: .blue)

        let after = try scene.render(color: .pink)

        #expect(before.pixels != after.pixels)
        #expect(stride(from: 3, to: before.pixels.count, by: 4).allSatisfy { before.pixels[$0] == after.pixels[$0] })
        #expect(scene.fluid.model.time == time)
        #expect(scene.fluid.model.fraction == fraction)
    }

}

/// 本番の転送・描画処理を、背景が透明なテクスチャへ実行するテスト用の場。
/// 各テストが独立して所有し、モデルやGPU資源をテスト間で共有しない。
@MainActor
private final class OffscreenWater {
    let fluid: FluidSimulation
    private let queue: any MTLCommandQueue
    private let pipelines: WaterRenderPipelines
    private let target: any MTLTexture
    private let width = 400
    private let height = 864

    init(fill: Double = 0.5, kind: FluidKind = .water) throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let library = try #require(device.makeDefaultLibrary())
        queue = try #require(device.makeCommandQueue())
        pipelines = try WaterRenderPipelines(device: device, library: library, pixelFormat: .rgba8Unorm)
        fluid = try FluidSimulation(device: device, aspectRatio: 2.16)
        var configuration = FluidConfiguration()
        configuration.fill = fill
        configuration.kind = kind
        configuration.flow = 0.16
        fluid.model.reset(configuration: configuration, start: true)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
            width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget]
        target = try #require(device.makeTexture(descriptor: descriptor))
    }

    func advance(frames: Int) {
        for _ in 0..<frames { fluid.model.advance(by: 1 / 60) }
    }

    func render(opacity: Double = 0.45, color: FluidColorChoice = .standard) throws -> RenderedWater {
        fluid.uploadSurface()
        let command = try #require(queue.makeCommandBuffer())
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        let encoder = try #require(command.makeRenderCommandEncoder(descriptor: pass))
        let uniforms = WaterUniforms(viewport: SIMD4(Float(width), Float(height), Float(opacity),
            Float(fluid.model.columnCount)), detail: fluid.model.visualDetails, palette: color.palette(for: fluid.model.configuration.kind))
        pipelines.encode(fluid, with: encoder, uniforms: uniforms)
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        try #require(command.status == .completed)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        target.getBytes(&pixels, bytesPerRow: width * 4,
                        from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return RenderedWater(width: width, height: height, pixels: pixels)
    }
}

private struct RenderedWater {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    func alpha(x: Int, y: Int) -> UInt8 { pixels[(y * width + x) * 4 + 3] }

    func save(frame: Int, prefix: String = "water") throws {
        let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
        let image = try #require(CGImage(width: width, height: height, bitsPerComponent: 8,
            bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent))
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(prefix)-frame-\(frame).png")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        try #require(CGImageDestinationFinalize(destination))
        print("Water render: \(url.path)")
    }
}

struct FluidBufferLayoutTests {
    @Test("共有頂点と定数のメモリ配置がMetalのバッファ仕様に一致する")
    func sharedLayoutsMatchMetal() {
        #expect(MemoryLayout<WaterVertex>.stride == 16)
        #expect(MemoryLayout<BubbleVertex>.stride == 32)
        #expect(MemoryLayout<WaterUniforms>.stride == 96)
        #expect(MemoryLayout<WaterVertex>.offset(of: \.texture) == 8)
        #expect(MemoryLayout<BubbleVertex>.offset(of: \.appearance) == 16)
        #expect(MemoryLayout<WaterUniforms>.offset(of: \.detail) == 16)
        #expect(MemoryLayout<WaterUniforms>.offset(of: \.shallowColor) == 32)
        #expect(MemoryLayout<WaterUniforms>.offset(of: \.edgeColor) == 80)
    }
}
