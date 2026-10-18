// SwiftUIに透明なMetalレイヤーを重ね、物理計算と描画のフレームを管理する。
import MetalKit
import SwiftUI

extension View {
    /// 適用先の大きさに合わせて液体を重ねる。操作と注水設定はcontrolsで管理する。
    ///
    /// - Parameters:
    ///   - controls: 呼び出し側で保持する操作状態。Viewの更新ごとに作り直さないこと。
    ///   - ignoresSafeArea: trueなら液体レイヤーだけをセーフエリアまで広げる。既定はfalse。
    ///
    /// 液体はタッチを遮らず、アクセシビリティの読み上げ対象にも含めない。
    /// 適用先のレイアウトサイズは変更しない。
    func liquidOverlay(controls: FluidControls, ignoresSafeArea: Bool = false) -> some View {
        modifier(LiquidOverlayModifier(controls: controls, ignoresSafeArea: ignoresSafeArea))
    }
}

/// 液体レイヤーの配置・タッチ透過・アクセシビリティ設定をまとめる。
private struct LiquidOverlayModifier: ViewModifier {
    let controls: FluidControls
    let ignoresSafeArea: Bool

    func body(content: Content) -> some View {
        content.overlay {
            LiquidOverlay(controls: controls)
                .ignoresSafeArea(.all, edges: ignoresSafeArea ? .all : [])
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// 背景の内容を読み取らず、任意の長方形領域へ水を重ねる。タッチは背景へ通す。
private struct LiquidOverlay: UIViewRepresentable {
    let controls: FluidControls
    @Environment(\.scenePhase) private var scenePhase

    // 描画状態はCoordinatorに保持し、SwiftUIのView更新ごとに作り直さない。
    func makeCoordinator() -> LiquidRenderer { LiquidRenderer(controls: controls) }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        // UIView・CALayer・Metalのクリア色をすべて透明にして背景を透過させる。
        view.backgroundColor = .clear
        view.isOpaque = false
        view.layer.isOpaque = false
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.colorPixelFormat = .bgra8Unorm
        view.preferredFramesPerSecond = 60
        view.isUserInteractionEnabled = false
        context.coordinator.attach(to: view)
        view.delegate = context.coordinator
        return view
    }

    /// 非アクティブ時は描画コールバックを止める。操作パネルの一時停止とは別の制御。
    func updateUIView(_ view: MTKView, context: Context) {
        view.isPaused = scenePhase != .active
    }

    /// 取り外し後に描画を続けないよう、コールバックとdelegate参照を解除する。
    static func dismantleUIView(_ view: MTKView, coordinator: LiquidRenderer) {
        view.isPaused = true
        view.delegate = nil
    }
}

/// 操作要求の消費順序と再生時刻を管理する。MetalやViewを持たず、停止中も操作を受け取る。
struct FluidPlayback {
    private var previousTime: CFTimeInterval?
    private var lastRestart = 0
    private var lastReset = 0

    mutating func advance(_ model: WaterModel, controls: FluidControls, now: CFTimeInterval) {
        consumeRequests(model, controls: controls)
        // 復帰や処理落ち後も大量の追いつき計算をしない。Floatへの丸めも従来どおり。
        let dt = Float(min(max(now - (previousTime ?? (now - 1 / 60)), 0), 1 / 60))
        previousTime = now
        if !controls.isPaused && (model.hasWater || model.isPouring) {
            model.advance(by: Double(dt))
        }
    }

    mutating func discardElapsedTime() { previousTime = nil }

    /// リサイズで空に戻した場合、直前の操作要求を新しい容器へ持ち越さない。
    mutating func acknowledgeRequests(from controls: FluidControls) {
        lastRestart = controls.restartID
        lastReset = controls.resetID
    }

    private mutating func consumeRequests(_ model: WaterModel, controls: FluidControls) {
        // リセットは、それ以前の再注水要求も処理済みにする。
        if controls.resetID != lastReset {
            model.reset(configuration: controls.configuration, start: false)
            acknowledgeRequests(from: controls)
        }
        if controls.restartID != lastRestart {
            model.reset(configuration: controls.configuration, start: true)
            lastRestart = controls.restartID
        }
    }
}

/// MTKViewのフレームを調停する。物理更新・描画設定・計測報告の詳細は各担当へ委ねる。
/// アプリ既定のMainActor隔離で、UI状態と共有バッファの変更を直列化する。
final class LiquidRenderer: NSObject, MTKViewDelegate {
    private let controls: FluidControls
    private var queue: (any MTLCommandQueue)?
    private var pipelines: WaterRenderPipelines?
    private var simulation: FluidSimulation?
    private var simulationAspect = 0.0
    // GPUが共有バッファを読んでいる間は書き換えない。同時実行は1フレームまで。
    private var pending = false
    private var playback = FluidPlayback()
    private var reportTime = CACurrentMediaTime()
    private var reportFrames = 0

    init(controls: FluidControls) { self.controls = controls }

    func attach(to view: MTKView) {
        do {
            guard let device = view.device, let queue = device.makeCommandQueue(),
                  let library = device.makeDefaultLibrary() else {
                throw FluidError.unavailable("この環境では Metal を初期化できませんでした。")
            }
            pipelines = try WaterRenderPipelines(device: device, library: library, pixelFormat: view.colorPixelFormat)
            self.queue = queue
        } catch {
            controls.error = error.localizedDescription
        }
    }

    /// サイズ変更前の時刻差を次のフレームへ持ち越さない。
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        playback.discardElapsedTime()
    }

    /// 描画先と前フレームの完了を確認してから、更新・転送・描画・完了通知を順に行う。
    func draw(in view: MTKView) {
        guard !pending, controls.error == nil,
              let device = view.device, let queue, let pipelines,
              view.drawableSize.width > 0, view.drawableSize.height > 0,
              let drawable = view.currentDrawable,
              let pass = view.currentRenderPassDescriptor,
              let command = queue.makeCommandBuffer() else { return }
        do {
            let simulation = try prepareSimulation(device: device, size: view.drawableSize)
            let simulationStart = CACurrentMediaTime()
            playback.advance(simulation.model, controls: controls, now: simulationStart)
            // 停止中も転送・描画して、不透明度などの表示設定を反映する。
            simulation.uploadSurface()
            let simulationMS = (CACurrentMediaTime() - simulationStart) * 1_000
            guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
                throw FluidError.unavailable("液体の描画コマンドを作成できませんでした。")
            }
            let uniforms = makeUniforms(size: view.drawableSize, model: simulation.model)
            pipelines.encode(simulation, with: encoder, uniforms: uniforms)
            encoder.endEncoding()
            command.present(drawable)
            submit(command, model: simulation.model, simulationMilliseconds: simulationMS)
        } catch {
            controls.error = error.localizedDescription
        }
    }

    private func prepareSimulation(device: any MTLDevice, size: CGSize) throws -> FluidSimulation {
        let aspect = size.height / size.width
        if let simulation, abs(simulationAspect - aspect) <= 0.01 { return simulation }
        // 容器の縦横比が変わると物理領域も変わるため、空から作り直す。
        let resizing = simulation != nil
        let replacement = try FluidSimulation(device: device, aspectRatio: aspect)
        simulation = replacement
        simulationAspect = aspect
        if resizing {
            controls.reset()
            controls.status = "画面サイズが変わったため空に戻しました"
            playback.acknowledgeRequests(from: controls)
        }
        return replacement
    }

    private func makeUniforms(size: CGSize, model: WaterModel) -> WaterUniforms {
        WaterUniforms(viewport: SIMD4(Float(size.width), Float(size.height),
            Float(controls.configuration.sanitized.opacity), Float(model.columnCount)), detail: model.visualDetails)
    }

    private func submit(_ command: any MTLCommandBuffer, model: WaterModel, simulationMilliseconds: Double) {
        pending = true
        let fraction = model.fraction
        let pouring = model.isPouring
        command.addCompletedHandler { @Sendable [weak self] completed in
            // MainActor外では値だけを取り出し、コマンドやモデルをUIタスクへ渡さない。
            let gpuMS = max(0, completed.gpuEndTime - completed.gpuStartTime) * 1_000
            let message = completed.error?.localizedDescription
            Task { @MainActor [weak self] in
                self?.completeFrame(gpuMilliseconds: gpuMS, simulationMilliseconds: simulationMilliseconds,
                                    fraction: fraction, pouring: pouring, error: message)
            }
        }
        command.commit()
    }

    private func completeFrame(gpuMilliseconds: Double, simulationMilliseconds: Double,
                               fraction: Double, pouring: Bool, error: String?) {
        pending = false
        if let error { controls.error = error }
        reportFrames += 1
        let now = CACurrentMediaTime()
        let interval = now - reportTime
        // Observationの更新は約0.5秒ごと。物理モデルの毎フレーム更新と分離する。
        guard interval >= 0.5 else { return }
        controls.framesPerSecond = Double(reportFrames) / interval
        controls.gpuMilliseconds = gpuMilliseconds
        controls.simulationMilliseconds = simulationMilliseconds
        controls.insertedFraction = fraction
        if !controls.isPaused {
            controls.status = pouring ? "注水中" : (fraction > 0 ? "注水完了・水面を計算中" : "注水して動きを確認")
        }
        reportFrames = 0
        reportTime = now
    }
}

/// alpha乗算済みの合成設定と描画順を一か所で管理する。オフスクリーン検証でも同じ経路を使う。
struct WaterRenderPipelines {
    private let surface: any MTLRenderPipelineState
    private let stream: any MTLRenderPipelineState
    private let splash: any MTLRenderPipelineState
    private let bubble: any MTLRenderPipelineState

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
    }

    func encode(_ simulation: FluidSimulation, with encoder: any MTLRenderCommandEncoder, uniforms: WaterUniforms) {
        var uniforms = uniforms
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<WaterUniforms>.stride, index: 0)
        // 水流 → 容器内の水 → 気泡 → 飛沫。水面より下の水流は容器内の水で覆う。
        drawVertices(simulation.streamBuffer, count: simulation.streamVertexCount,
                     primitive: .triangleStrip, pipeline: stream, encoder: encoder)
        encoder.setRenderPipelineState(surface)
        encoder.setFragmentBuffer(simulation.surfaceBuffer, offset: 0, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        drawVertices(simulation.bubbleBuffer, count: simulation.bubbleVertexCount,
                     primitive: .triangle, pipeline: bubble, encoder: encoder)
        drawVertices(simulation.splashBuffer, count: simulation.splashVertexCount,
                     primitive: .triangle, pipeline: splash, encoder: encoder)
    }

    private func drawVertices(_ buffer: any MTLBuffer, count: Int, primitive: MTLPrimitiveType,
                              pipeline: any MTLRenderPipelineState, encoder: any MTLRenderCommandEncoder) {
        guard count > 0 else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: primitive, vertexStart: 0, vertexCount: count)
    }
}
