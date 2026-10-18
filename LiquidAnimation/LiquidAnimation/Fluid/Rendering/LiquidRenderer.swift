import MetalKit
import QuartzCore

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
