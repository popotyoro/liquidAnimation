import SwiftUI

extension View {
    /// 下から指定割合まで塗る。withAnimationで割合を変えると水位が補間される。
    /// タッチ・レイアウトは変えず、角丸などのクリップは呼び出し側で指定する。
    /// 範囲外は0...1に補正し、NaN・無限大は0として扱う。
    func liquidFill(fraction: Double, color: Color = .cyan.opacity(0.3)) -> some View {
        modifier(LiquidFillModifier(fraction: fraction, color: color))
    }
}
