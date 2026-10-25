import CoreGraphics
import Foundation
import ImageIO
import Metal
import Testing
import UniformTypeIdentifiers
@testable import LiquidFluid

@MainActor
struct WaterRenderingTests {
    @Test("25%の水を残して40%まで追加注水する様子を描画する",
          arguments: [0, 8, 30, 60, 120, 360], [FluidKind.water, .beer])
    func additionalPourRendersFromExistingLevel(frame: Int, kind: FluidKind) throws {
        // 準備
        let scene = try OffscreenWater(fill: 0.4, kind: kind, initialFraction: 0.25)
        scene.advance(frames: frame)

        // 実行
        let image = try scene.render()

        // 検証
        #expect(image.alpha(x: image.width / 2, y: image.height * 7 / 8) > 0)
        #expect(scene.fluid.model.fraction >= 0.25)
        #expect(scene.fluid.model.fraction <= 0.4 + 1e-10)
        try image.attach(frame: frame, prefix: "addition-\(kind.rawValue)")
    }

    @Test("着水中と注水後の各時点で液体を描画する", arguments: [60, 90, 120, 150, 180, 210, 240, 480])
    func impactSurfaceRendersAtRequestedTime(frame: Int) throws {
        // 準備
        let scene = try OffscreenWater()
        scene.advance(frames: frame)

        // 実行
        let image = try scene.render()

        // 検証
        #expect(image.hasVisibleLiquid)
        try image.attach(frame: frame, prefix: "water-impact")
    }

    @Test("泡の生成から排液後までビールを描画する", arguments: [60, 120, 240, 600, 1200])
    func beerFoamRendersAtRequestedTime(frame: Int) throws {
        // 準備
        let scene = try OffscreenWater(kind: .beer)
        scene.advance(frames: frame)

        // 実行
        let image = try scene.render()

        // 検証
        #expect(image.hasVisibleLiquid)
        try image.attach(frame: frame, prefix: "beer-foam")
    }

    @Test("50%まで溜まった水のない画面上部は透明になる")
    func settledPoolLeavesUpperContainerTransparent() throws {
        // 準備
        let scene = try OffscreenWater()
        scene.advance(frames: 480)

        // 実行
        let image = try scene.render()

        // 検証
        #expect(image.alpha(x: image.width / 2, y: image.height / 4) == 0)
    }

    @Test("50%まで溜まった水は指定した不透明度で描く", arguments: [0.0, 0.45, 1.0])
    func settledPoolUsesConfiguredOpacity(opacity: Double) throws {
        // 準備
        let scene = try OffscreenWater()
        scene.advance(frames: 480)

        // 実行
        let image = try scene.render(opacity: opacity)

        // 検証
        #expect(abs(Int(image.alpha(x: image.width / 2, y: image.height * 3 / 4)) - Int((opacity * 255).rounded())) <= 1)
        if opacity == 0.45 { try image.attach(frame: 480) }
    }

    @Test("静止した水面は壁際だけ少し持ち上がり中央はほぼ50%に保つ")
    func settledPoolRisesSlightlyAtWalls() throws {
        // 準備
        let scene = try OffscreenWater()
        scene.advance(frames: 480)

        // 実行
        let image = try scene.render()

        // 検証
        let aboveSurface = image.height / 2 - 2
        #expect(image.alpha(x: 2, y: aboveSurface) > 100)
        #expect(image.alpha(x: image.width - 3, y: aboveSurface) > 100)
        #expect(image.alpha(x: image.width / 2, y: aboveSurface) == 0)
    }

    @Test("空の容器には液体を描かない")
    func emptyContainerRendersNothing() throws {
        // 準備
        let scene = try OffscreenWater(fill: 0)
        scene.advance(frames: 60)

        // 実行
        let image = try scene.render()

        // 検証
        #expect(image.pixels.allSatisfy { $0 == 0 })
    }

    @Test("不透明度0では注水中の水流・水面・飛沫・気泡を描かない")
    func zeroOpacityHidesEveryWaterLayer() throws {
        // 準備
        let scene = try OffscreenWater()
        scene.advance(frames: 120)
        try #require(scene.fluid.model.bubbleCount > 0)
        try #require(scene.fluid.model.splashCount > 0)

        // 実行
        let image = try scene.render(opacity: 0)

        // 検証
        #expect(image.pixels.allSatisfy { $0 == 0 })
    }

    @Test("注水開始と減流中も水流が描画される", arguments: [8, 195])
    func rampingJetRemainsVisible(frame: Int) throws {
        // 準備
        let scene = try OffscreenWater()
        scene.advance(frames: frame)

        // 実行
        let image = try scene.render()

        // 検証
        #expect(image.hasVisiblePixels(above: image.height / 4))
        try image.attach(frame: frame)
    }

    @Test("注水中の気泡を描画対象に含める")
    func pouringWaterIncludesEntrainedBubbles() throws {
        // 準備
        let scene = try OffscreenWater()
        scene.advance(frames: 120)

        // 実行
        let image = try scene.render()

        // 検証
        #expect(scene.fluid.bubbleVertexCount > 0)
        try image.attach(frame: 120)
    }

    @Test("注水後に静止すると巻き込まれた気泡は描画対象からなくなる")
    func entrainedBubblesDisappearAfterPouring() throws {
        // 準備
        let scene = try OffscreenWater()
        scene.advance(frames: 120)
        try #require(scene.fluid.model.bubbleCount > 0)

        // 実行
        scene.advance(frames: 360)
        _ = try scene.render()

        // 検証
        #expect(scene.fluid.bubbleVertexCount == 0)
    }

    @Test("入口を止めても未着水の水流は描画される")
    func stoppedInletKeepsFallingWaterVisible() throws {
        // 準備
        let scene = try OffscreenWater()
        scene.advance(frames: 210)
        try #require(!scene.fluid.model.isPouring)

        // 実行
        let image = try scene.render()

        // 検証
        #expect(scene.fluid.streamVertexCount > 0)
        try image.attach(frame: 210)
    }

    @Test("分離した水流の末尾は容器へ戻るまで水滴の描画対象になる")
    func separatedTailRendersAsDrops() throws {
        // 準備
        let scene = try OffscreenWater()
        scene.advance(frames: 214)
        try #require(scene.fluid.model.detachedDropCount > 0)

        // 実行
        let image = try scene.render()

        // 検証
        #expect(scene.fluid.splashVertexCount > 0)
        try image.attach(frame: 214)
    }

    @Test("どの液体も注水中の容器の底を塗る", arguments: FluidKind.allCases)
    func everyPresetRenders(kind: FluidKind) throws {
        // 準備
        let scene = try OffscreenWater(kind: kind)
        scene.advance(frames: 120)

        // 実行
        let image = try scene.render()

        // 検証
        #expect(image.alpha(x: image.width / 2, y: image.height - 10) > 0)
        try image.attach(frame: 120, prefix: kind.rawValue)
    }

    @Test("どの種類も不透明度0では全描画パスが透明になる", arguments: FluidKind.allCases)
    func everyPresetSupportsZeroOpacity(kind: FluidKind) throws {
        // 準備
        let scene = try OffscreenWater(kind: kind)
        scene.advance(frames: 120)

        // 実行
        let image = try scene.render(opacity: 0)

        // 検証
        #expect(image.pixels.allSatisfy { $0 == 0 })
    }

    @Test("注水し直さず色だけを変えると描画色が変わる")
    func colorChangesWithoutRestarting() throws {
        // 準備
        let scene = try OffscreenWater()
        scene.advance(frames: 480)
        let before = try scene.render(color: .blue)

        // 実行
        let after = try scene.render(color: .pink)

        // 検証
        #expect(before.pixels != after.pixels)
    }

    @Test("描画色を変えても液体の輪郭と不透明度は変わらない")
    func colorChangePreservesAlpha() throws {
        // 準備
        let scene = try OffscreenWater()
        scene.advance(frames: 480)
        let before = try scene.render(color: .blue)

        // 実行
        let after = try scene.render(color: .pink)

        // 検証
        #expect(stride(from: 3, to: before.pixels.count, by: 4).allSatisfy { before.pixels[$0] == after.pixels[$0] })
    }

    @Test("描画色を変えてもシミュレーションの時刻と投入量は変わらない")
    func colorChangeDoesNotAdvanceSimulation() throws {
        // 準備
        let scene = try OffscreenWater()
        scene.advance(frames: 480)
        _ = try scene.render(color: .blue)
        let time = scene.fluid.model.time
        let fraction = scene.fluid.model.fraction

        // 実行
        _ = try scene.render(color: .pink)

        // 検証
        #expect(scene.fluid.model.time == time)
        #expect(scene.fluid.model.fraction == fraction)
    }

    @Test("静止した液体は水面近くより深い部分ほど暗くなる", arguments: FluidColorChoice.allCases)
    func deeperLiquidHasDarkerColor(color: FluidColorChoice) throws {
        // 準備
        let scene = try OffscreenWater()
        scene.advance(frames: 480)

        // 実行
        let image = try scene.render(opacity: 1, color: color)

        // 検証。中央列の水面から離れた2点で、反射の縁を除いて比較する。
        let x = image.width / 2
        let shallowY = image.height * 5 / 8
        let deepY = image.height * 7 / 8
        #expect(image.luminance(x: x, y: deepY) < image.luminance(x: x, y: shallowY))
        #expect(image.alpha(x: x, y: deepY) == image.alpha(x: x, y: shallowY))
    }

    @Test("物理状態が同じなら反射と厚みの質感は再描画しても変わらない")
    func repeatedRenderingKeepsMaterialStill() throws {
        // 準備
        let scene = try OffscreenWater()
        scene.advance(frames: 120)
        let before = try scene.render()

        // 実行
        let after = try scene.render()

        // 検証
        #expect(after.pixels == before.pixels)
    }

    @Test("注水後の炭酸気泡は400px幅で直径4.5px以上になる", arguments: [FluidKind.beer, .sparklingWater])
    func carbonationOutlinesMeetMinimumDiameter(kind: FluidKind) throws {
        // 準備
        let scene = try OffscreenWater(kind: kind)
        scene.advance(frames: 600)

        // 実行
        let bubbles = scene.fluid.model.bubbleVertices()

        // 検証
        try #require(!bubbles.isEmpty)
        for start in stride(from: 0, to: bubbles.count, by: 6) {
            let diameter = abs(bubbles[start + 1].position.x - bubbles[start].position.x) * 400
            #expect(diameter >= 4.5)
        }
    }

    @Test("注水後の炭酸気泡は白い背景でも見分けられる", arguments: [FluidKind.beer, .sparklingWater])
    func carbonationHasVisibleContrast(kind: FluidKind) throws {
        // 準備
        let scene = try OffscreenWater(kind: kind)
        scene.advance(frames: 600)
        try #require(scene.fluid.model.bubbleCount > 0)

        // 実行
        let withBubbles = try scene.render()
        let withoutBubbles = try scene.render(hidesBubbles: true)

        // 検証
        // 白い背景へ合成したときも、泡の有無で5%以上違う画素が十分にある。
        let visiblePixels = stride(from: 0, to: withBubbles.pixels.count, by: 4).filter { i in
            (0..<3).contains { channel in
                let a = Int(withBubbles.pixels[i + channel]) + 255 - Int(withBubbles.pixels[i + 3])
                let b = Int(withoutBubbles.pixels[i + channel]) + 255 - Int(withoutBubbles.pixels[i + 3])
                return abs(a - b) >= 13
            }
        }.count
        #expect(visiblePixels >= 150)
        try withBubbles.attach(frame: 600, prefix: kind.rawValue)
    }

}

/// 本番の転送・描画処理を、背景が透明なテクスチャへ実行するテスト用の場。
/// 各テストが独立して所有し、モデルやGPU資源をテスト間で共有しない。
/// 各描画でGPUの完了を待つため、後始末はテスト終了時のARCによる解放で完了する。
@MainActor
private final class OffscreenWater {
    let fluid: FluidSimulation
    private let queue: any MTLCommandQueue
    private let pipelines: WaterRenderPipelines
    private let target: any MTLTexture
    private let width = 400
    private let height = 864

    init(fill: Double = 0.5, kind: FluidKind = .water, initialFraction: Double = 0) throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let library = try WaterRenderPipelines.makeLibrary(device: device)
        queue = try #require(device.makeCommandQueue())
        pipelines = try WaterRenderPipelines(device: device, library: library, pixelFormat: .rgba8Unorm)
        fluid = try FluidSimulation(device: device, aspectRatio: 2.16)
        var configuration = FluidConfiguration()
        configuration.fill = fill
        configuration.kind = kind
        configuration.flow = 0.16
        fluid.model.reset(configuration: configuration, start: true, initialFraction: initialFraction)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
            width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget]
        target = try #require(device.makeTexture(descriptor: descriptor))
    }

    func advance(frames: Int) {
        for _ in 0..<frames { fluid.model.advance(by: 1 / 60) }
    }

    func render(opacity: Double = 0.45, color: FluidColorChoice = .standard, hidesBubbles: Bool = false) throws -> RenderedWater {
        fluid.uploadSurface()
        if hidesBubbles {
            let vertices = fluid.bubbleBuffer.contents().bindMemory(to: BubbleVertex.self, capacity: fluid.bubbleVertexCount)
            for i in 0..<fluid.bubbleVertexCount { vertices[i].appearance.x = 0 }
        }
        let command = try #require(queue.makeCommandBuffer())
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        let uniforms = WaterUniforms(viewport: SIMD4(Float(width), Float(height), Float(opacity),
            Float(fluid.model.columnCount)), detail: fluid.model.visualDetails, palette: color.palette(for: fluid.model.configuration.kind))
        try pipelines.prepareSurface(fluid, command: command, uniforms: uniforms)
        let encoder = try #require(command.makeRenderCommandEncoder(descriptor: pass))
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

    var hasVisibleLiquid: Bool {
        hasVisiblePixels(above: height)
    }

    func hasVisiblePixels(above maximumY: Int) -> Bool {
        stride(from: 3, to: width * maximumY * 4, by: 4).contains { pixels[$0] > 0 }
    }

    func alpha(x: Int, y: Int) -> UInt8 { pixels[(y * width + x) * 4 + 3] }

    func luminance(x: Int, y: Int) -> Double {
        let offset = (y * width + x) * 4
        return 0.2126 * Double(pixels[offset]) + 0.7152 * Double(pixels[offset + 1])
            + 0.0722 * Double(pixels[offset + 2])
    }

    func attach(frame: Int, prefix: String = "water") throws {
        let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
        let image = try #require(CGImage(width: width, height: height, bitsPerComponent: 8,
            bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent))
        let png = try #require(CFDataCreateMutable(kCFAllocatorDefault, 0))
        let destination = try #require(CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        try #require(CGImageDestinationFinalize(destination))
        Attachment.record(png as Data, named: "\(prefix)-frame-\(frame).png")
    }
}

struct FluidBufferLayoutTests {
    @Test("水の頂点はMetalが読む16バイトの配置と一致する")
    func waterVertexMatchesMetalLayout() {
        // 準備・実行
        let stride = MemoryLayout<WaterVertex>.stride
        let textureOffset = MemoryLayout<WaterVertex>.offset(of: \.texture)

        // 検証
        #expect(stride == 16)
        #expect(textureOffset == 8)
    }

    @Test("気泡の頂点はMetalが読む32バイトの配置と一致する")
    func bubbleVertexMatchesMetalLayout() {
        // 準備・実行
        let stride = MemoryLayout<BubbleVertex>.stride
        let appearanceOffset = MemoryLayout<BubbleVertex>.offset(of: \.appearance)

        // 検証
        #expect(stride == 32)
        #expect(appearanceOffset == 16)
    }

    @Test("描画定数はMetalが読む112バイトの配置と一致する")
    func waterUniformsMatchMetalLayout() {
        // 準備・実行
        let stride = MemoryLayout<WaterUniforms>.stride
        let detailOffset = MemoryLayout<WaterUniforms>.offset(of: \.detail)
        let shallowColorOffset = MemoryLayout<WaterUniforms>.offset(of: \.shallowColor)
        let edgeColorOffset = MemoryLayout<WaterUniforms>.offset(of: \.edgeColor)
        let foamOffset = MemoryLayout<WaterUniforms>.offset(of: \.foam)

        // 検証
        #expect(stride == 112)
        #expect(detailOffset == 16)
        #expect(shallowColorOffset == 32)
        #expect(edgeColorOffset == 80)
        #expect(foamOffset == 96)
    }
}
