import simd

/// 気泡と飛沫を描画用の三角形へ変換する。物理モデルを更新しない。
struct WaterParticleMeshBuilder {
    let width: Double
    let height: Double
    private static let corners: [SIMD2<Double>] = [SIMD2(-1,-1), SIMD2(1,-1), SIMD2(-1,1),
                                                 SIMD2(-1,1), SIMD2(1,-1), SIMD2(1,1)]

    /// 気泡を四角形へ展開する。輪郭と小さな反射光はMetal側で描く。
    func bubbleVertices(_ bubbles: [WaterModel.Bubble]) -> [BubbleVertex] {
        var vertices: [BubbleVertex] = []
        vertices.reserveCapacity(bubbles.count * 6)
        for bubble in bubbles {
            let fade = min(1, bubble.age / 0.10, (bubble.lifetime - bubble.age) / 0.3)
            // 炭酸の泡には画面幅の1.2%の最小直径を与え、小さな点へ潰れるのを防ぐ。
            let radius = bubble.isCarbonated ? max(bubble.radius, width * 0.006) : bubble.radius
            for corner in Self.corners {
                let point = bubble.position + corner * radius
                vertices.append(BubbleVertex(
                    position: normalizedPosition(point),
                    texture: SIMD2(Float(corner.x), Float(-corner.y)),
                    appearance: SIMD4(Float(fade), bubble.isCarbonated ? 1 : 0, 0, 0)))
            }
        }
        return vertices
    }

    /// 飛沫を速度方向に伸ばした楕円の四角形メッシュへ変換する。
    /// 縦横の伸縮率を逆数にして面積を保ち、輪郭はフラグメント側で切り抜く。
    func splashVertices(_ drops: [WaterModel.Drop]) -> [WaterVertex] {
        var vertices: [WaterVertex] = []
        vertices.reserveCapacity(drops.count * 6)
        for drop in drops {
            let speed = simd_length(drop.velocity)
            let axis = speed > 0.01 ? drop.velocity / speed : SIMD2(0, 1)
            let normal = SIMD2(axis.y, -axis.x)
            let stretch = 1.5 + min(1.5, speed)
            let radius = sqrt(drop.area / .pi)
            for corner in Self.corners {
                let point = drop.position + normal * corner.x * radius / sqrt(stretch)
                    + axis * corner.y * radius * sqrt(stretch)
                vertices.append(WaterVertex(position: normalizedPosition(point),
                                            texture: SIMD2(Float(corner.x), Float(corner.y))))
            }
        }
        return vertices
    }

    /// 物理座標（m、下向きy）を描画座標（0〜1、上向きy）へ変換する。
    func normalizedPosition(_ point: SIMD2<Double>) -> SIMD2<Float> {
        SIMD2(Float(point.x / width), Float(1 - point.y / height))
    }
}
