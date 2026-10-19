import SwiftUI

/// 水位だけを補間する軽量な形状。物理演算や常時更新のループは持たない。
@Animatable
nonisolated struct LiquidFillShape: Shape {
    var fraction: Double

    func path(in rect: CGRect) -> Path {
        let level = Self.boundedFraction(fraction)
        guard level > 0 else { return Path() }
        let height = rect.height * level
        return Path(CGRect(x: rect.minX, y: rect.maxY - height, width: rect.width, height: height))
    }

    static func boundedFraction(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0
    }
}
