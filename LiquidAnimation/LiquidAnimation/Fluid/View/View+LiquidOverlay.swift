import SwiftUI

extension View {
    /// 適用先の大きさに合わせて液体を重ねる。操作と注水設定はcontrolsで管理する。
    ///
    /// - Parameters:
    ///   - controls: 呼び出し側で保持する操作状態。Viewの更新ごとに作り直さないこと。
    ///   - ignoresSafeArea: trueなら液体レイヤーだけをセーフエリアまで広げる。既定はfalse。
    ///
    /// 液体はタッチを遮らず、アクセシビリティの読み上げ対象にも含めない。
    /// 適用先のレイアウトサイズは変更しない。
    func liquidOverlay(controls: FluidControls, ignoresSafeArea: Bool = false) -> some View {
        modifier(LiquidOverlayModifier(controls: controls, ignoresSafeArea: ignoresSafeArea))
    }
}
