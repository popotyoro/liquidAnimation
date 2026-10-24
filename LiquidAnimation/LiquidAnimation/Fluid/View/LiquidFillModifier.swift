import SwiftUI

/// 水位は呼び出し側が補間し、割合が変わったときだけ有限時間の波を重ねる。
struct LiquidFillModifier: ViewModifier {
    let fraction: Double
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            KeyframeAnimator(initialValue: 1.0, trigger: LiquidFillShape.boundedFraction(fraction)) { progress in
                LiquidFillShape(fraction: LiquidFillShape.boundedFraction(fraction),
                                waveProgress: reduceMotion ? 1 : progress)
                    .fill(color)
            } keyframes: { _ in
                MoveKeyframe(0)
                LinearKeyframe(1, duration: reduceMotion ? 0 : 2.6)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
