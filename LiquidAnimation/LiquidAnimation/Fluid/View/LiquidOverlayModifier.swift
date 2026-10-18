import SwiftUI

/// 液体レイヤーの配置・タッチ透過・アクセシビリティ設定をまとめる。
struct LiquidOverlayModifier: ViewModifier {
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
