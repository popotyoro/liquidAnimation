import MetalKit
import SwiftUI

/// 背景の内容を読み取らず、任意の長方形領域へ水を重ねる。タッチは背景へ通す。
struct LiquidOverlay: UIViewRepresentable {
    let controls: FluidControls
    var isActive = true
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
        view.isPaused = scenePhase != .active || !isActive
    }

    /// 取り外し後に描画を続けないよう、コールバックとdelegate参照を解除する。
    static func dismantleUIView(_ view: MTKView, coordinator: LiquidRenderer) {
        view.isPaused = true
        view.delegate = nil
    }
}
