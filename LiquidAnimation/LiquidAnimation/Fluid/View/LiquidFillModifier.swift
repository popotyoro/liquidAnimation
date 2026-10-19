import SwiftUI

/// 適用先の下から液体を重ねる。時間と再生状態は呼び出し側が管理する。
struct LiquidFillModifier: ViewModifier {
    let fraction: Double
    let color: Color

    func body(content: Content) -> some View {
        content.overlay {
            LiquidFillShape(fraction: LiquidFillShape.boundedFraction(fraction))
                .fill(color)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
