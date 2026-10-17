// SwiftUIに透明なMetalレイヤーを重ね、物理計算と描画のフレームを管理する。
import MetalKit
import SwiftUI

/// 背景の内容を読み取らず、任意の長方形領域へ水を重ねる。タッチは背景へ通す。
struct LiquidOverlay: UIViewRepresentable {
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

/// MTKViewのフレームごとに操作を反映し、モデル更新・転送・描画を行う。
/// アプリ既定のMainActor隔離で、UI状態と共有バッファの変更を直列化する。
final class LiquidRenderer: NSObject, MTKViewDelegate {
    private let controls: FluidControls
    private var queue: (any MTLCommandQueue)?
    private var library: (any MTLLibrary)?
    private var renderPipeline: (any MTLRenderPipelineState)?
    private var bubblePipeline: (any MTLRenderPipelineState)?
    private var splashPipeline: (any MTLRenderPipelineState)?
    private var streamPipeline: (any MTLRenderPipelineState)?
    private var simulation: FluidSimulation?
    private var simulationAspect = 0.0
    // 共有バッファをGPUが読んでいる間にCPUが書き換えないよう、同時実行を1フレームに制限する。
    // pendingの参照・更新もMainActor上で行う。
    private var pending = false
    private var previousTime: CFTimeInterval?
    private var reportTime = CACurrentMediaTime()
    private var reportFrames = 0
    private var lastRestart = 0
    private var lastReset = 0

    init(controls: FluidControls) { self.controls = controls }

    /// 初期化時に4種類の描画パイプラインを作り、毎フレームの生成を避ける。
    func attach(to view: MTKView) {
        do {
            guard let device = view.device, let queue = device.makeCommandQueue(),
                  let library = device.makeDefaultLibrary() else {
                throw FluidError.unavailable("この環境では Metal を初期化できませんでした。")
            }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "waterVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "waterFragment")
            let attachment = descriptor.colorAttachments[0]!
            attachment.pixelFormat = view.colorPixelFormat
            // シェーダーが返す色はalpha乗算済み。背景へ one / oneMinusSourceAlpha で合成する。
            attachment.isBlendingEnabled = true
            attachment.sourceRGBBlendFactor = .one
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            renderPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            descriptor.vertexFunction = library.makeFunction(name: "streamVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "streamFragment")
            streamPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            descriptor.fragmentFunction = library.makeFunction(name: "splashFragment")
            splashPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            descriptor.vertexFunction = library.makeFunction(name: "bubbleVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "bubbleFragment")
            bubblePipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            self.queue = queue
            self.library = library
        } catch {
            controls.error = error.localizedDescription
        }
    }

    /// サイズ変更前の時刻差を次のフレームへ持ち越さない。
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        previousTime = nil
    }

    /// GPUの前フレームが完了し、描画先を確保できたときだけ次のフレームを処理する。
    func draw(in view: MTKView) {
        guard !pending, controls.error == nil,
              let device = view.device, library != nil, let queue, let renderPipeline, let streamPipeline, let splashPipeline, let bubblePipeline,
              view.drawableSize.width > 0, view.drawableSize.height > 0,
              let drawable = view.currentDrawable,
              let pass = view.currentRenderPassDescriptor,
              let command = queue.makeCommandBuffer() else { return }
        do {
            // 容器の縦横比が変わると物理領域も変わるため、量の再配置はせず空から作り直す。
            let aspect = view.drawableSize.height / view.drawableSize.width
            if simulation == nil || abs(simulationAspect - aspect) > 0.01 {
                let resizing = simulation != nil
                simulation = try FluidSimulation(device: device, aspectRatio: aspect)
                simulationAspect = aspect
                if resizing {
                    controls.reset()
                    controls.status = "画面サイズが変わったため空に戻しました"
                    lastRestart = controls.restartID
                    lastReset = controls.resetID
                }
            }
            guard let simulation else { return }
            // UIの操作IDを消費する。リセット時は過去の再注水要求も処理済みにする。
            if controls.resetID != lastReset {
                simulation.model.reset(configuration: controls.configuration, start: false)
                lastReset = controls.resetID
                lastRestart = controls.restartID
            }
            if controls.restartID != lastRestart {
                simulation.model.reset(configuration: controls.configuration, start: true)
                lastRestart = controls.restartID
            }
            let now = CACurrentMediaTime()
            // 復帰や処理落ち後も大量の追いつき計算をせず、最大1/60秒だけ進める。
            let dt = Float(min(max(now - (previousTime ?? (now - 1 / 60)), 0), 1 / 60))
            previousTime = now
            let simulationStart = CACurrentMediaTime()
            if !controls.isPaused && (simulation.model.hasWater || simulation.model.isPouring) {
                simulation.model.advance(by: Double(dt))
            }
            // 一時停止中も転送・描画は行い、不透明度などの表示設定を反映する。
            simulation.uploadSurface()
            let simulationMS = (CACurrentMediaTime() - simulationStart) * 1_000
            guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
                throw FluidError.unavailable("液体の描画コマンドを作成できませんでした。")
            }
            var uniforms = WaterUniforms(viewport: SIMD4(
                Float(view.drawableSize.width), Float(view.drawableSize.height),
                Float(controls.configuration.sanitized.opacity), Float(simulation.model.columnCount)))
            uniforms.detail = simulation.model.visualDetails
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<WaterUniforms>.stride, index: 0)
            // 水流 → 容器内の水 → 気泡 → 飛沫の順。水面より下の水流は容器内の水で覆う。
            if simulation.streamVertexCount > 0 {
                encoder.setRenderPipelineState(streamPipeline)
                encoder.setVertexBuffer(simulation.streamBuffer, offset: 0, index: 0)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: simulation.streamVertexCount)
            }
            encoder.setRenderPipelineState(renderPipeline)
            encoder.setFragmentBuffer(simulation.surfaceBuffer, offset: 0, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            if simulation.bubbleVertexCount > 0 {
                encoder.setRenderPipelineState(bubblePipeline)
                encoder.setVertexBuffer(simulation.bubbleBuffer, offset: 0, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: simulation.bubbleVertexCount)
            }
            if simulation.splashVertexCount > 0 {
                encoder.setRenderPipelineState(splashPipeline)
                encoder.setVertexBuffer(simulation.splashBuffer, offset: 0, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: simulation.splashVertexCount)
            }
            encoder.endEncoding()
            command.present(drawable)
            pending = true
            let fraction = simulation.model.fraction
            let pouring = simulation.model.isPouring
            command.addCompletedHandler { @Sendable [weak self] completed in
                // この通知はMainActor外で届く。時刻とエラー文字列だけを取り出し、
                // コマンドバッファや変更可能なモデルをUIタスクへ渡さない。
                let gpuMS = max(0, completed.gpuEndTime - completed.gpuStartTime) * 1_000
                let message = completed.error?.localizedDescription
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.pending = false
                    if let message { self.controls.error = message }
                    self.reportFrames += 1
                    let reportNow = CACurrentMediaTime()
                    let interval = reportNow - self.reportTime
                    // 毎フレームObservationを更新せず、計測表示は約0.5秒ごとにまとめる。
                    if interval >= 0.5 {
                        self.controls.framesPerSecond = Double(self.reportFrames) / interval
                        self.controls.gpuMilliseconds = gpuMS
                        self.controls.simulationMilliseconds = simulationMS
                        self.controls.insertedFraction = fraction
                        if !self.controls.isPaused {
                            self.controls.status = pouring ? "注水中" :
                                (fraction > 0 ? "注水完了・水面を計算中" : "注水して動きを確認")
                        }
                        self.reportFrames = 0
                        self.reportTime = reportNow
                    }
                }
            }
            command.commit()
        } catch {
            controls.error = error.localizedDescription
        }
    }
}
