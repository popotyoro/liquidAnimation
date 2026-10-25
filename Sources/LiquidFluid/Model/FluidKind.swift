import Foundation

/// 選択できる液体のプリセット。物性は次回の注水時に確定する。
public nonisolated enum FluidKind: String, CaseIterable, Identifiable, Sendable {
    case water, beer, sparklingWater, viscousWater

    public var id: String { rawValue }

    var material: FluidMaterial {
        switch self {
        case .water: FluidMaterial()
        case .beer: FluidMaterial(momentumDamping: 3.2, splashScale: 0.8,
            bubbleRadiusScale: 0.65, carbonationInterval: 0.08)
        case .sparklingWater: FluidMaterial(bubbleRadiusScale: 0.5,
            entrainmentInterval: 0.025, carbonationInterval: 0.035)
        case .viscousWater: FluidMaterial(momentumDamping: 18, inletSpeed: 1.1,
            splashScale: 0.04, impactScale: 0.35, streamWobble: 0.18,
            bubbleRadiusScale: 0.75, entrainmentInterval: 0.15, separatesTail: false)
        }
    }
}
