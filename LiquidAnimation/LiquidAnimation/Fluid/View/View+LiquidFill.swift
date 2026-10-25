import SwiftUI

extension View {
    /// 下から指定割合まで塗る。withAnimationで割合を変えると水位が補間される。
    /// 割合の変更を波のトリガーにする。最後は平らな水面に戻る。
    /// タッチ・レイアウトは変えず、角丸などのクリップは呼び出し側で指定する。
    /// 範囲外は0...1に補正し、NaN・無限大は0として扱う。
    func liquidFill(fraction: Double, color: Color = .cyan.opacity(0.3)) -> some View {
        liquidFill(fraction: fraction, color: color, animationTrigger: fraction)
    }

    /// 液位の目標値とは別の状態変化で波を開始する。
    func liquidFill(fraction: Double, color: Color = .cyan.opacity(0.3), animationTrigger: Double) -> some View {
        modifier(LiquidFillModifier(fraction: fraction, color: color, animationTrigger: animationTrigger))
    }
}
