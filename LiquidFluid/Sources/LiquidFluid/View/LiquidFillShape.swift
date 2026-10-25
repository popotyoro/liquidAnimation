import SwiftUI

/// 水位と短い減衰波を描く軽量な形状。物理演算や常時更新のループは持たない。
@Animatable
nonisolated struct LiquidFillShape: Shape {
    var fraction: Double
    // 進行率はKeyframeAnimatorが補間するため、Shape側で重ねて補間しない。
    @AnimatableIgnored var waveProgress: Double = 1

    func path(in rect: CGRect) -> Path {
        let level = Self.boundedFraction(fraction)
        guard level > 0 else { return Path() }
        let height = rect.height * level
        let surfaceY = rect.maxY - height
        let progress = Self.boundedFraction(waveProgress)
        guard progress > 0, progress < 1, level < 1 else {
            return Path(CGRect(x: rect.minX, y: surfaceY, width: rect.width, height: height))
        }

        // 幅の整数周期の波を重ね、平均水位を保つ。浅い水と満水付近では振幅を制限する。
        let envelope = 1.8 * sin(.pi * progress) * exp(-1.8 * progress)
        let amplitude = min(3, rect.width * 0.045, height, rect.height - height) * envelope
        let phase = progress * 6 * .pi
        var path = Path()
        for index in 0...32 {
            let x = Double(index) / 32
            let wave = 0.75 * sin(2 * .pi * x + phase) + 0.25 * sin(4 * .pi * x - phase)
            let point = CGPoint(x: rect.minX + rect.width * x, y: surfaceY + amplitude * wave)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }

    static func boundedFraction(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0
    }
}
