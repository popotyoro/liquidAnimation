import SwiftUI

extension Color {
    /// 既存の標準色・明示色・不透明度の設定を、軽量なSwiftUI描画でも共用する。
    static func liquidFill(for configuration: FluidConfiguration) -> Color {
        let configuration = configuration.sanitized
        let rgb = configuration.color.palette(for: configuration.kind).shallow
        return Color(.sRGB, red: Double(rgb.x), green: Double(rgb.y), blue: Double(rgb.z),
                     opacity: configuration.opacity)
    }
}
