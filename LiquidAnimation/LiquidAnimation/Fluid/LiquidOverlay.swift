import MetalKit
import SwiftUI

/// Overlays any rectangular view without reading its contents or intercepting touches.
struct LiquidOverlay: UIViewRepresentable {
    let controls: FluidControls
    @Environment(\.scenePhase) private var scenePhase

    func makeCoordinator() -> LiquidRenderer { LiquidRenderer(controls: controls) }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
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

    func updateUIView(_ view: MTKView, context: Context) {
        view.isPaused = scenePhase != .active
    }

    static func dismantleUIView(_ view: MTKView, coordinator: LiquidRenderer) {
        view.isPaused = true
        view.delegate = nil
    }
}

@MainActor
final class LiquidRenderer: NSObject, MTKViewDelegate {
    private let controls: FluidControls
    private var queue: (any MTLCommandQueue)?
    private var library: (any MTLLibrary)?
    private var renderPipeline: (any MTLRenderPipelineState)?
    private var streamPipeline: (any MTLRenderPipelineState)?
    private var simulation: FluidSimulation?
    private var simulationAspect = 0.0
    private var pending = false
    private var previousTime: CFTimeInterval?
    private var reportTime = CACurrentMediaTime()
    private var reportFrames = 0
    private var lastRestart = 0
    private var lastReset = 0

    init(controls: FluidControls) { self.controls = controls }

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
            attachment.isBlendingEnabled = true
            attachment.sourceRGBBlendFactor = .one
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            renderPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            descriptor.vertexFunction = library.makeFunction(name: "streamVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "streamFragment")
            streamPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            self.queue = queue
            self.library = library
        } catch {
            controls.error = error.localizedDescription
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        previousTime = nil
    }

    func draw(in view: MTKView) {
        guard !pending, controls.error == nil,
              let device = view.device, library != nil, let queue, let renderPipeline, let streamPipeline,
              view.drawableSize.width > 0, view.drawableSize.height > 0,
              let drawable = view.currentDrawable,
              let pass = view.currentRenderPassDescriptor,
              let command = queue.makeCommandBuffer() else { return }
        do {
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
            let dt = Float(min(max(now - (previousTime ?? (now - 1 / 60)), 0), 1 / 60))
            previousTime = now
            let simulationStart = CACurrentMediaTime()
            if !controls.isPaused && (simulation.model.hasWater || simulation.model.isPouring) {
                simulation.model.advance(by: Double(dt))
            }
            simulation.uploadSurface()
            let simulationMS = (CACurrentMediaTime() - simulationStart) * 1_000
            guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
                throw FluidError.unavailable("液体の描画コマンドを作成できませんでした。")
            }
            var uniforms = WaterUniforms(viewport: SIMD4(
                Float(view.drawableSize.width), Float(view.drawableSize.height),
                Float(controls.configuration.sanitized.opacity), Float(simulation.model.columnCount)))
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<WaterUniforms>.stride, index: 0)
            if simulation.streamVertexCount > 0 {
                encoder.setRenderPipelineState(streamPipeline)
                encoder.setVertexBuffer(simulation.streamBuffer, offset: 0, index: 0)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: simulation.streamVertexCount)
            }
            encoder.setRenderPipelineState(renderPipeline)
            encoder.setFragmentBuffer(simulation.surfaceBuffer, offset: 0, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
            command.present(drawable)
            pending = true
            let fraction = simulation.model.fraction
            let pouring = simulation.model.isPouring
            command.addCompletedHandler { [weak self] completed in
                let gpuMS = max(0, completed.gpuEndTime - completed.gpuStartTime) * 1_000
                let message = completed.error?.localizedDescription
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.pending = false
                    if let message { self.controls.error = message }
                    self.reportFrames += 1
                    let reportNow = CACurrentMediaTime()
                    let interval = reportNow - self.reportTime
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
