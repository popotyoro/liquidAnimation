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
    private var simulation: FluidSimulation?
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
            descriptor.vertexFunction = library.makeFunction(name: "fluidVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "fluidFragment")
            let attachment = descriptor.colorAttachments[0]!
            attachment.pixelFormat = view.colorPixelFormat
            attachment.isBlendingEnabled = true
            attachment.sourceRGBBlendFactor = .one
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            renderPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
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
              let device = view.device, let library, let queue, let renderPipeline,
              view.drawableSize.width > 0, view.drawableSize.height > 0,
              let drawable = view.currentDrawable,
              let pass = view.currentRenderPassDescriptor,
              let command = queue.makeCommandBuffer() else { return }
        do {
            let aspect = view.drawableSize.height / view.drawableSize.width
            let expectedHeight = min(256, max(32, Int((64 * aspect).rounded())))
            if simulation == nil || simulation?.ny != expectedHeight {
                let resizing = simulation != nil
                simulation = try FluidSimulation(device: device, library: library, aspectRatio: aspect)
                if resizing {
                    controls.reset()
                    controls.status = "画面サイズが変わったため空に戻しました"
                    lastRestart = controls.restartID
                    lastReset = controls.resetID
                }
            }
            guard let simulation else { return }
            if controls.resetID != lastReset {
                simulation.reset(configuration: controls.configuration, start: false)
                lastReset = controls.resetID
                lastRestart = controls.restartID
            }
            if controls.restartID != lastRestart {
                simulation.reset(configuration: controls.configuration, start: true)
                lastRestart = controls.restartID
            }
            let now = CACurrentMediaTime()
            let dt = Float(min(max(now - (previousTime ?? (now - 1 / 60)), 0), 1 / 60))
            previousTime = now
            simulation.diagnostics.contents().storeBytes(of: UInt32(0), as: UInt32.self)
            try simulation.encodeFrame(commandBuffer: command, deltaTime: dt,
                                       opacity: controls.configuration.sanitized.opacity,
                                       advance: !controls.isPaused &&
                                        (simulation.particleCount > 0 || simulation.isPouring))
            guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
                throw FluidError.unavailable("液体の描画コマンドを作成できませんでした。")
            }
            encoder.setRenderPipelineState(renderPipeline)
            encoder.setFragmentTexture(simulation.surface, index: 0)
            var uniforms = simulation.uniforms
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FluidUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
            command.present(drawable)
            pending = true
            let fraction = simulation.fraction
            let pouring = simulation.isPouring
            command.addCompletedHandler { [weak self] completed in
                let gpuMS = max(0, completed.gpuEndTime - completed.gpuStartTime) * 1_000
                let message = completed.error?.localizedDescription
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.pending = false
                    if let message { self.controls.error = message }
                    if simulation.diagnostics.contents().load(as: UInt32.self) > 0 {
                        self.controls.error = "液体が一か所に集中し、計算の上限を超えました。リセットしてください。"
                    }
                    self.reportFrames += 1
                    let reportNow = CACurrentMediaTime()
                    let interval = reportNow - self.reportTime
                    if interval >= 0.5 {
                        self.controls.framesPerSecond = Double(self.reportFrames) / interval
                        self.controls.gpuMilliseconds = gpuMS
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
