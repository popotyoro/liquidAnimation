import Foundation
import simd

/// 水深を水平1次元で解く浅水モデルと、水流・飛沫の水量管理を組み合わせる。
/// 長さはm、断面積はm²、momentumは水深×水平速度（m²/s）。
/// 水面の巻き返りや内部の渦は解かず、着水圧力と飛沫を近似的に加える。
final class WaterModel {
    let columnCount: Int
    let width = 0.75
    let height: Double
    // 各列の水深と流量。列境界のフラックスで隣の列へ水・運動量を移す。
    private(set) var depths: [Double]
    private var momentum: [Double]
    private var heightFlux: [Double]
    private var momentumFlux: [Double]
    private(set) var impactPressure: [Double] // 圧力÷密度（m²/s²）。着水点のへこみを作る。
    private var impactImpulse: [Double]
    private(set) var configuration = FluidConfiguration()
    // 投入総量 = 水面内の量 + 水流の量 + 飛沫の量。空中分も目標量に含める。
    private(set) var emittedArea = 0.0
    private(set) var landedArea = 0.0
    private(set) var time = 0.0
    /// 着水済みの量のうち、泡の膜に保持される液体（m²）。landedAreaの内数。
    private(set) var foamLiquidArea = 0.0
    /// 液中に巻き込まれた微細気泡の白濁度。0〜1の描画用近似。
    private(set) var beerCloudiness = 0.0
    /// 保持量から白濁域の厚さへ変換する表示用近似。液面の内側だけを覆う。
    var foamHeight: Double { foamLiquidArea / width / 0.40 }
    private var parcels: [Parcel] = []
    static let maximumDrops = 96

    private var drops: [Drop] = []
    private var attemptedTailSeparation = false
    private var separatedTailStart: Double?
    private(set) var separatedTailArea = 0.0
    var detachedDropCount: Int { drops.filter(\.detachedFromStream).count }
    private var lastSplashTime = -1.0
    private var splashSequence = 0
    var splashCount: Int { drops.count }
    var splashFraction: Double { drops.reduce(0) { $0 + $1.area } / capacity }
    var jetFraction: Double { parcels.reduce(0) { $0 + $1.area } / capacity }
    // 気泡は空気を表す装飾。水深・運動量・投入量へは影響を与えない。
    static let maximumBubbles = 128

    private var bubbles: [Bubble] = []
    private var lastBubbleTime = -1.0
    private var bubbleSequence = 0
    private var lastCarbonationTime = -1.0
    private var carbonationSequence = 0
    private var material = FluidMaterial()
    var bubbleCount: Int { bubbles.count }
    var visualDetails: SIMD4<Float> {
        let sum = impactPressure.reduce(0, +)
        let center = sum > 1e-9 ? impactPressure.enumerated().reduce(0.0) {
            $0 + (Double($1.offset) + 0.5) / Double(columnCount) * $1.element
        } / sum : 0
        return SIMD4(Float(center), Float((impactPressure.max() ?? 0) / (gravity * 0.06)),
                     Float(time), Float(height / width))
    }
    private var targetArea = 0.0
    private let gravity = 9.81
    private var inletSpeed: Double { material.inletSpeed }
    private let dryDepth = 1e-7

    private var nominalRate: Double { configuration.flow * capacity }
    private var emission: PourEmission { PourEmission(targetArea: targetArea, nominalRate: nominalRate) }
    private var rampDuration: Double { emission.rampDuration }
    var pourDuration: Double { emission.duration }
    var inletRate: Double { emission.rate(at: time) }

    private func emissionRate(at instant: Double) -> Double { emission.rate(at: instant) }
    private func cumulativeEmission(at instant: Double) -> Double { emission.cumulativeArea(at: instant) }

    var capacity: Double { width * height }
    var fraction: Double { emittedArea / capacity }
    var landedFraction: Double { landedArea / capacity }
    /// 水流と飛沫の合計。飛沫への振り分けでは投入総量を変えない。
    var airborneFraction: Double { max(0, emittedArea - landedArea) / capacity }
    var isPouring: Bool { emittedArea < targetArea - 1e-12 }
    var hasWater: Bool { emittedArea > 0 }
    var meanDepth: Double { depths.reduce(0, +) / Double(columnCount) }
    var surfaceRange: Double { (depths.max() ?? 0) - (depths.min() ?? 0) }
    /// 水平運動のエネルギー指標。注水後の減衰をテストするために使う。
    var kineticEnergy: Double {
        zip(depths, momentum).reduce(0) { sum, value in
            sum + (value.0 > dryDepth ? value.1 * value.1 / (2 * value.0) : 0)
        } * dx
    }
    private var dx: Double { width / Double(columnCount) }
    private var angle: Double { configuration.angle * .pi / 180 }
    private var inletVelocity = SIMD2(0.0, 1.6)

    /// 幅0.75mを基準に、表示領域の縦横比から容器の高さを決める。
    init(aspectRatio: Double, columnCount: Int = 128) {
        self.columnCount = max(16, columnCount)
        height = width * min(4, max(0.5, aspectRatio))
        depths = .init(repeating: 0, count: self.columnCount)
        momentum = depths
        heightFlux = .init(repeating: 0, count: self.columnCount + 1)
        momentumFlux = heightFlux
        impactPressure = depths
        impactImpulse = depths
    }

    /// 設定を確定し、空中の水・水面・圧力・時刻をまとめて初期化する。
    func reset(configuration: FluidConfiguration, start: Bool) {
        self.configuration = configuration.sanitized
        material = self.configuration.kind.material
        inletVelocity = SIMD2(inletSpeed * sin(angle), inletSpeed * cos(angle))
        targetArea = start ? self.configuration.fill * capacity : 0
        emittedArea = 0
        landedArea = 0
        time = 0
        foamLiquidArea = 0
        beerCloudiness = 0
        parcels.removeAll(keepingCapacity: true)
        drops.removeAll(keepingCapacity: true)
        attemptedTailSeparation = false
        separatedTailStart = nil
        separatedTailArea = 0
        lastSplashTime = -1
        splashSequence = 0
        bubbles.removeAll(keepingCapacity: true)
        lastBubbleTime = -1
        bubbleSequence = 0
        lastCarbonationTime = -1
        carbonationSequence = 0
        for i in depths.indices {
            depths[i] = 0
            momentum[i] = 0
            impactPressure[i] = 0
            impactImpulse[i] = 0
        }
    }

    /// CFL条件に従う小刻みな更新で数値計算を安定させる。遅延分の大量計算はしない。
    func advance(by duration: Double) {
        guard duration.isFinite, duration > 0 else { return }
        var remaining = min(duration, 1.0 / 30)
        while remaining > 1e-9 {
            let dt = stableTimeStep(remaining: remaining)
            time += dt
            emitWater(dt: dt)
            let previousLandedArea = landedArea
            // 飛沫を戻す → 水流を着水させる → 圧力を更新 → 水面を進める、の順で処理する。
            advanceDrops(dt: dt)
            advanceBubbles(dt: dt)
            spawnCarbonationBubble()
            for i in impactImpulse.indices { impactImpulse[i] = 0 }
            depositArrivals()
            updateFoam(dt: dt, arrivingArea: max(0, landedArea - previousLandedArea))
            detachThinTail()
            updateImpactPressure(dt: dt)
            solveShallowWater(dt: dt)
            remaining -= dt
        }
        preserveVolume()
    }

    /// 注ぎ始めは90%を泡に保持し、たまるにつれて12%へ下げる。
    /// 6秒の時定数で排液し、下の液体へ戻す。係数は見た目のための近似。
    private func updateFoam(dt: Double, arrivingArea: Double) {
        guard configuration.kind == .beer else { return }
        let foamingFraction = 0.12 + 0.78 * exp(-landedFraction / 0.08)
        foamLiquidArea = min(landedArea,
            foamLiquidArea * exp(-dt / 6) + arrivingArea * foamingFraction)
        // 着水で白濁し、注水を止めると微細気泡の浮上を近似して透明に戻す。
        // 更新間隔に依存しない指数応答。液体の体積・運動量は変えない。
        let clearing = beerCloudiness * exp(-dt / 2.4)
        let entrainment = 1 - exp(-arrivingArea / (capacity * 0.025))
        beerCloudiness = clearing + (1 - clearing) * entrainment
    }

    /// 波速と流速に対して、1ステップでセルを飛び越えない刻みを選ぶ。
    private func stableTimeStep(remaining: Double) -> Double {
        var maxSpeed = 0.1
        for i in depths.indices {
            let velocity = depths[i] > dryDepth ? abs(momentum[i] / depths[i]) : 0
            maxSpeed = max(maxSpeed, velocity + sqrt(gravity * depths[i]))
        }
        return min(remaining, 1.0 / 240, 0.4 * dx / maxSpeed)
    }

    private func emitWater(dt: Double) {
        guard isPouring else { return }
        let amount = min(max(0, cumulativeEmission(at: time) - emittedArea), targetArea - emittedArea)
        emittedArea += amount
        // 各区間の代表時刻は時間刻みの中央に置く。
        if amount > 0 { parcels.append(Parcel(time: min(time - dt / 2, pourDuration), area: amount)) }
    }

    /// 初速と重力から水流の中心軌道を求める。壁ではxを固定して下へ流す。
    /// 負のageは入口を画面外へ延ばす描画用で、上流へ直線的に延長する。
    private func flightPosition(age: Double) -> SIMD2<Double> {
        let x = configuration.sourcePosition * width + inletVelocity.x * age
        let y = inletVelocity.y * age + 0.5 * gravity * max(0, age) * max(0, age)
        return SIMD2(min(max(x, 0.002), width - 0.002), y)
    }

    /// 水面に達した区間を水流から取り除き、水面と飛沫へ面積を振り分ける。
    private func depositArrivals() {
        var survivors: [Parcel] = []
        survivors.reserveCapacity(parcels.count)
        // 同じ刻みで追加した水深を次の着水判定へ使うと、落下中の水が連鎖的に
        // 吸い込まれてしまう。全区間を、更新前の同じ水面で判定する。
        let collisionDepths = depths
        for parcel in parcels {
            let age = time - parcel.time
            let point = flightPosition(age: age)
            let column = min(columnCount - 1, max(0, Int(point.x / dx)))
            if point.y < height - collisionDepths[column] {
                survivors.append(parcel)
                continue
            }
            let impactSpeed = inletVelocity.y + gravity * age
            if collisionDepths[column] > 0.035, time - lastBubbleTime >= material.entrainmentInterval,
               emissionRate(at: parcel.time) > nominalRate * 0.05 {
                spawnBubbles(at: point.x, surface: height - collisionDepths[column], impactSpeed: impactSpeed)
            }
            let splashArea = launchSplashes(for: parcel, at: point, column: column, impactSpeed: impactSpeed)
            applyImpactImpulse(area: parcel.area, at: point.x, column: column, impactSpeed: impactSpeed)
            depositWater(area: parcel.area - splashArea, at: point.x, column: column,
                         emittedAt: parcel.time, impactSpeed: impactSpeed)
        }
        parcels = survivors
    }

    /// 着水量の一部だけを飛沫へ回し、間隔・同時数・上昇速度を制限する。
    private func launchSplashes(for parcel: Parcel, at point: SIMD2<Double>, column: Int,
                               impactSpeed: Double) -> Double {
        var splashArea = 0.0
        if depths[column] > 0.008, height - depths[column] > 0.025,
           time - lastSplashTime > 0.025, drops.count + 2 <= Self.maximumDrops {
            splashArea = parcel.area * 0.32 * material.splashScale
            lastSplashTime = time
            splashSequence += 1
            for side in [-1.0, 1.0] {
                let variation = 0.8 + 0.2 * sin(Double(splashSequence) * 2.4 + side)
                let rise = min(1.15, impactSpeed * 0.28) * variation * material.splashScale
                let offset = configuration.flow * capacity / impactSpeed * 0.6 + dx
                let x = min(width - 0.002, max(0.002, point.x + side * offset))
                let launchColumn = min(columnCount - 1, max(0, Int(x / dx)))
                let position = SIMD2(x, max(0, height - depths[launchColumn] - 0.012))
                drops.append(Drop(position: position,
                    velocity: SIMD2(side * rise * 0.8 + inletVelocity.x * 0.15, -rise),
                    area: splashArea / 2))
            }
        }
        return splashArea
    }

    /// 未解像の鉛直衝撃を、数セル以上の幅を持つ圧力の入力へ変換する。
    private func applyImpactImpulse(area: Double, at x: Double, column: Int, impactSpeed: Double) {
        let sigma = max(2.5 * dx, configuration.flow * capacity / impactSpeed * 0.65)
        let footprint = GaussianFootprint(x: x, column: column, sigma: sigma, dx: dx, columnCount: columnCount)
        for i in footprint.columns {
            impactImpulse[i] += area * impactSpeed * footprint.normalizedWeight(at: i) / dx
        }
    }

    /// 水流の幅で着水量を配り、上端近くの局所的な水深の急増を防ぐ。
    private func depositWater(area: Double, at x: Double, column: Int, emittedAt: Double, impactSpeed: Double) {
        landedArea += area
        let sigma = max(1.5 * dx, emissionRate(at: emittedAt) / impactSpeed * 0.45)
        let footprint = GaussianFootprint(x: x, column: column, sigma: sigma, dx: dx, columnCount: columnCount)
        let horizontal = inletVelocity.x
        for i in footprint.columns {
            let addedDepth = area * footprint.normalizedWeight(at: i) / dx
            depths[i] += addedDepth
            // 外向きの運動量で着水の広がりを近似する。水の量は増やさない。
            let outward = 0.30 * impactSpeed * tanh(Double(i - column))
            momentum[i] += addedDepth * (horizontal * 0.35 + outward)
        }
    }

    /// 小さな比較試作として、停止後の細い末尾だけを最大3滴へ分ける。
    /// 表面張力による分裂は解かず、減流区間の最後の40%を対象とする。
    private func detachThinTail() {
        guard material.separatesTail, !attemptedTailSeparation, targetArea > 0, !isPouring,
              time >= pourDuration + 0.05 else { return }
        attemptedTailSeparation = true
        let cutTime = pourDuration - rampDuration * 0.4
        let tail = parcels.filter { $0.time >= cutTime }
        guard tail.count >= 3, drops.count + 3 <= Self.maximumDrops else { return }
        var areas = [Double](repeating: 0, count: 3)
        var moments = areas
        for parcel in tail {
            let group = min(2, max(0, Int((parcel.time - cutTime) / (pourDuration - cutTime) * 3)))
            areas[group] += parcel.area
            moments[group] += parcel.time * parcel.area
        }
        for group in areas.indices where areas[group] > 0 {
            let age = time - moments[group] / areas[group]
            let point = flightPosition(age: age)
            let onWall = point.x <= 0.002 || point.x >= width - 0.002
            drops.append(Drop(position: point,
                velocity: SIMD2(onWall ? 0 : inletVelocity.x, inletVelocity.y + gravity * age),
                area: areas[group], detachedFromStream: true))
        }
        // 水流から除いた面積をそのまま水滴へ移す。投入量・着水済み量は変えない。
        separatedTailArea = areas.reduce(0, +)
        separatedTailStart = cutTime
        parcels.removeAll { $0.time >= cutTime }
    }

    /// 飛沫を重力で落とし、壁では減速、水面への再突入では全量を戻す。
    private func advanceDrops(dt: Double) {
        var survivors: [Drop] = []
        survivors.reserveCapacity(drops.count)
        for var drop in drops {
            drop.velocity.y += gravity * dt
            drop.position += drop.velocity * dt
            // 壁で水平速度の85%を失わせる非弾性反射。水面では反射させない。
            if drop.position.x < 0 || drop.position.x > width {
                drop.position.x = min(width, max(0, drop.position.x))
                drop.velocity.x *= -0.15
            }
            if drop.position.y < 0 {
                drop.position.y = 0
                drop.velocity.y = max(0, drop.velocity.y)
            }
            let column = min(columnCount - 1, max(0, Int(drop.position.x / dx)))
            // 上昇中の飛沫を直後の盛り上がりで消さず、落下中に水面へ戻ったとき吸収する。
            if drop.velocity.y >= 0 && drop.position.y >= height - depths[column] {
                landedArea += drop.area
                depths[column] += drop.area / dx
                momentum[column] += drop.area / dx * drop.velocity.x * 0.25
            } else {
                survivors.append(drop)
            }
        }
        drops = survivors
    }

    /// 着水点から空気が巻き込まれる様子を、最大2個ずつの気泡で近似する。
    private func spawnBubbles(at x: Double, surface: Double, impactSpeed: Double) {
        guard bubbles.count + 2 <= Self.maximumBubbles else { return }
        lastBubbleTime = time
        bubbleSequence += 1
        for side in [-1.0, 1.0] {
            let phase = Double(bubbleSequence) * 2.399 + side
            let variation = 0.5 + 0.5 * sin(phase)
            let radius = (0.002 + 0.004 * variation) * material.bubbleRadiusScale
            bubbles.append(Bubble(
                position: SIMD2(min(width - radius, max(radius, x + side * (0.005 + variation * 0.012))),
                                min(height - radius, surface + 0.012 + radius * 2)),
                velocity: SIMD2(side * (0.03 + variation * 0.08), min(0.45, impactSpeed * 0.10)),
                radius: radius, age: 0, lifetime: 1.8 + variation, phase: phase))
        }
    }

    /// 溶存ガスの装飾的な気泡。水量や圧力は変えず、注水後も液体内に発生させる。
    private func spawnCarbonationBubble() {
        guard let interval = material.carbonationInterval, landedArea > 0,
              time - lastCarbonationTime >= interval else { return }
        lastCarbonationTime = time
        guard bubbles.count < Self.maximumBubbles else { return }
        carbonationSequence += 1
        // 発生点・大きさ・揺れの位相を独立した疑似乱数で散らす。
        // 同じ注水条件では同じ並びになり、見た目の比較を再現できる。
        let variation = carbonationSample(channel: 1)
        let phase = carbonationSample(channel: 2) * 2 * .pi
        let x = width * (0.08 + 0.84 * carbonationSample(channel: 0))
        let column = min(columnCount - 1, max(0, Int(x / dx)))
        guard depths[column] > 0.035 else { return }
        let radius = (0.005 + 0.005 * variation) * material.bubbleRadiusScale
        let y = height - radius * 2 - (0.004 + 0.012 * carbonationSample(channel: 3))
        let riseSpeed = 0.18 + radius * 16
        // 深い場所でも途中で消えず水面まで上がれる時間を確保する。
        bubbles.append(Bubble(position: SIMD2(x, y), velocity: SIMD2(0, -riseSpeed),
            radius: radius, age: 0, lifetime: depths[column] / riseSpeed + 0.6,
            phase: phase, isCarbonated: true))
    }

    /// 発生番号と用途から0以上1未満の値を作る。状態を持たないSplitMix64の混合。
    private func carbonationSample(channel: UInt64) -> Double {
        var value = UInt64(carbonationSequence) &+ (channel &+ 1) &* 0x9E3779B97F4A7C15
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        value ^= value >> 31
        return Double(value >> 11) / 9_007_199_254_740_992
    }

    /// 最初は下へ巻き込まれ、抵抗と浮力の近似で上昇する。合体・分裂・水への反作用は解かない。
    private func advanceBubbles(dt: Double) {
        var survivors: [Bubble] = []
        survivors.reserveCapacity(bubbles.count)
        for var bubble in bubbles {
            bubble.age += dt
            guard bubble.age < bubble.lifetime else { continue }
            let column = min(columnCount - 1, max(0, Int(bubble.position.x / dx)))
            guard depths[column] > bubble.radius * 3 else { continue }
            let waterSpeed = depths[column] > dryDepth ? momentum[column] / depths[column] : 0
            let target: SIMD2<Double>
            if bubble.isCarbonated {
                target = SIMD2(waterSpeed * 0.05 + sin(bubble.age * 5 + bubble.phase) * 0.008,
                               -0.18 - bubble.radius * 16)
            } else {
                target = SIMD2(waterSpeed * 0.15 + sin(bubble.age * 8 + bubble.phase) * 0.035,
                               -0.10 - bubble.radius * 14)
            }
            bubble.velocity += (target - bubble.velocity) * (1 - exp(-4 * dt))
            bubble.position += bubble.velocity * dt
            bubble.position.x = min(width - bubble.radius, max(bubble.radius, bubble.position.x))
            let destination = min(columnCount - 1, max(0, Int(bubble.position.x / dx)))
            // 浮上して水面へ触れた気泡は消す。水の量は変わらない。
            guard bubble.position.y - bubble.radius > height - depths[destination],
                  bubble.position.y + bubble.radius < height else { continue }
            survivors.append(bubble)
        }
        bubbles = survivors
    }

    /// 気泡を四角形へ展開する。輪郭と小さな反射光はMetal側で描く。
    func bubbleVertices() -> [BubbleVertex] {
        let corners: [SIMD2<Double>] = [SIMD2(-1,-1), SIMD2(1,-1), SIMD2(-1,1),
                                      SIMD2(-1,1), SIMD2(1,-1), SIMD2(1,1)]
        var vertices: [BubbleVertex] = []
        vertices.reserveCapacity(bubbles.count * 6)
        for bubble in bubbles {
            let fade = min(1, bubble.age / 0.10, (bubble.lifetime - bubble.age) / 0.3)
            // 炭酸の泡には画面幅の1.2%の最小直径を与え、小さな点へ潰れるのを防ぐ。
            let radius = bubble.isCarbonated ? max(bubble.radius, width * 0.006) : bubble.radius
            for corner in corners {
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
    func splashVertices() -> [WaterVertex] {
        var vertices: [WaterVertex] = []
        vertices.reserveCapacity(drops.count * 6)
        let corners: [SIMD2<Double>] = [SIMD2(-1,-1), SIMD2(1,-1), SIMD2(-1,1),
                                      SIMD2(-1,1), SIMD2(1,-1), SIMD2(1,1)]
        for drop in drops {
            let speed = simd_length(drop.velocity)
            let axis = speed > 0.01 ? drop.velocity / speed : SIMD2(0, 1)
            let normal = SIMD2(axis.y, -axis.x)
            let stretch = 1.5 + min(1.5, speed)
            let radius = sqrt(drop.area / .pi)
            for corner in corners {
                let point = drop.position + normal * corner.x * radius / sqrt(stretch)
                    + axis * corner.y * radius * sqrt(stretch)
                vertices.append(WaterVertex(position: normalizedPosition(point),
                                            texture: SIMD2(Float(corner.x), Float(corner.y))))
            }
        }
        return vertices
    }

    /// 着水の衝撃から水面を押す圧力を作る。着水が止まると目標値も0になる。
    private func updateImpactPressure(dt: Double) {
        // 水深平均の外力は -h ∂(p/ρ)/∂x。応答時間60msで離散的な着水を平滑化する。
        // 結合係数0.12と水頭6cmの上限は、未解像の鉛直運動を安定させる近似。
        let response = 1 - exp(-dt / 0.06)
        for i in depths.indices {
            let target = min(gravity * 0.06, 0.12 * impactImpulse[i] / dt) * material.impactScale
            impactPressure[i] += (target - impactPressure[i]) * response
        }
    }

    /// 水深hと水平流量q=huを有限体積法で更新する。圧力勾配は運動量だけに作用する。
    private func solveShallowWater(dt: Double) {
        calculateFaceFluxes()
        integrateDepthAndMomentum(dt: dt)
    }

    private func calculateFaceFluxes() {
        // Rusanov流束 F=(hu, hu²/h + gh²/2) を列境界で計算する。
        // 両端では仮想セルの流量の符号を反転し、壁を通る水量を0にする。
        // 右セルの値を次の面の左セルへ引き継ぎ、除算・平方根を再計算しない。
        var hL = depths[0]
        var qL = -momentum[0]
        var uL = hL > dryDepth ? qL / hL : 0
        var speedL = abs(uL) + sqrt(gravity * hL)
        for face in 0...columnCount {
            let right = min(columnCount - 1, face)
            let hR = depths[right]
            let qR = face == columnCount ? -momentum[right] : momentum[right]
            let uR = hR > dryDepth ? qR / hR : 0
            let speedR = abs(uR) + sqrt(gravity * hR)
            let speed = max(speedL, speedR)
            heightFlux[face] = 0.5 * (qL + qR) - 0.5 * speed * (hR - hL)
            momentumFlux[face] = 0.5 * (qL * uL + qR * uR + 0.5 * gravity * (hL*hL + hR*hR))
                - 0.5 * speed * (qR - qL)
            hL = hR
            qL = qR
            uL = uR
            speedL = speedR
        }
    }

    private func integrateDepthAndMomentum(dt: Double) {
        let ratio = dt / dx
        // 指数減衰は時間刻みを変えても同じ時間あたりの減衰率になる。
        let drag = exp(-material.momentumDamping * dt)
        for i in depths.indices {
            depths[i] = max(0, depths[i] - ratio * (heightFlux[i + 1] - heightFlux[i]))
            let left = max(0, i - 1), right = min(columnCount - 1, i + 1)
            let pressureGradient = (impactPressure[right] - impactPressure[left]) / (Double(right - left) * dx)
            momentum[i] = (momentum[i] - ratio * (momentumFlux[i + 1] - momentumFlux[i])
                           - depths[i] * pressureGradient * dt) * drag
            if depths[i] <= dryDepth { momentum[i] = 0 }
            else { momentum[i] = min(max(momentum[i], -2.5 * depths[i]), 2.5 * depths[i]) }
        }
    }

    /// 数値誤差を補正し、Σ(水深×セル幅)を着水済み面積へ一致させる。
    private func preserveVolume() {
        // 全列へ同じ高さを足す補正量を二分探索する。上下限内では波形を保つ。
        // 水深を0〜容器高さへ制限し、100%時にも容器の上へはみ出さないようにする。
        let desiredSum = landedArea / dx
        let currentSum = depths.reduce(0, +)
        if abs(currentSum - desiredSum) < 1e-10 && (depths.max() ?? 0) <= height { return }
        // 全列が上下限に触れない場合は、同じ一様補正を解析的に求められる。
        // 乾いた列・満水付近など、クリップが必要な場合だけ二分探索する。
        let uniformShift = (desiredSum - currentSum) / Double(columnCount)
        if (depths.min() ?? 0) + uniformShift >= 0,
           (depths.max() ?? 0) + uniformShift <= height {
            applyVolumeShift(uniformShift)
            return
        }
        var low = -max(height, depths.max() ?? 0), high = height
        for _ in 0..<44 {
            let shift = (low + high) / 2
            let sum = depths.reduce(0) { $0 + min(height, max(0, $1 + shift)) }
            if sum < desiredSum { low = shift } else { high = shift }
        }
        let shift = (low + high) / 2
        applyVolumeShift(shift)
    }

    private func applyVolumeShift(_ shift: Double) {
        for i in depths.indices {
            let old = depths[i]
            depths[i] = min(height, max(0, old + shift))
            if depths[i] < dryDepth { momentum[i] = 0 }
            else if old > dryDepth { momentum[i] *= min(1, depths[i] / old) }
        }
    }

    // 基本97 + 増減区間24 + 先端17 + 分離後の末尾12断面。各断面は左右2頂点。
    static let maximumStreamVertices = 300

    /// 投入時刻ごとの流量から水流の帯を作る。物理モデルの水量は変更しない。
    func streamVertices() -> [WaterVertex] {
        guard let first = parcels.first else { return [] }
        let profile = streamProfile(first: first)
        let ages = streamSampleAges(profile: profile)
        var vertices: [WaterVertex] = []
        vertices.reserveCapacity(Self.maximumStreamVertices)
        for (index, age) in ages.enumerated() {
            let section = streamCrossSection(at: age, profile: profile)
            for side in [-1.0, 1.0] {
                let edge = section.point + side * section.halfWidth * section.normal
                vertices.append(WaterVertex(position: normalizedPosition(edge),
                    texture: SIMD2(Float(side), Float(index) / Float(ages.count - 1))))
            }
        }
        return vertices
    }


    private func streamProfile(first: Parcel) -> StreamProfile {
        // 角度が大きい場合も入口の切断面が画面内に見えないよう、上流を画面外へ延ばす。
        let inletExtension = -(nominalRate / inletSpeed + 0.02) / inletVelocity.y
        let youngest = isPouring ? inletExtension : max(0, time - (separatedTailStart ?? pourDuration))
        var oldest = time - first.time
        // 最古の未着水区間は水面の手前にある。近接時だけ描画上の先端を補間し、隙間を抑える。
        let head = flightPosition(age: oldest)
        let headColumn = min(columnCount - 1, max(0, Int(head.x / dx)))
        let nearSurface = height - depths[headColumn] - head.y < 0.02
        if nearSurface && (isPouring || parcels.count > 1) {
            for _ in 0..<32 {
                let head = flightPosition(age: oldest)
                let column = min(columnCount - 1, max(0, Int(head.x / dx)))
                if head.y >= height - depths[column] { break }
                oldest += 1.0 / 960
            }
        }
        // 開始時の薄い水を先端の小さなふくらみとして描き、長い針状の輪郭を避ける。
        // 初期に投入した量から大きさを決めるが、これは表面張力を解かない描画上の近似。
        // 最初の水が着水した後は適用せず、既存の着水点の描画へ引き継ぐ。
        let freeHead = landedArea == 0 && !nearSurface
        let headSpeed = simd_length(SIMD2(inletVelocity.x, inletVelocity.y + gravity * oldest))
        let initialArea = cumulativeEmission(at: min(time * 0.5, rampDuration * 0.5))
        let headRadius = freeHead ? min(0.02, sqrt(initialArea / .pi)) : 0
        let headDuration = min(max(0, oldest - max(0, youngest)), 2 * headRadius / headSpeed)
        // 水滴に移した領域を帯でつなぎ直さず、残った帯の末尾を丸く閉じる。
        let tailSpeed = simd_length(SIMD2(inletVelocity.x, inletVelocity.y + gravity * max(0, youngest)))
        let tailRadius = emissionRate(at: separatedTailStart ?? pourDuration) / (2 * tailSpeed)
        let tailDuration = min(max(0, oldest - youngest), tailRadius / tailSpeed)
        return StreamProfile(youngest: youngest, oldest: oldest, headRadius: headRadius,
                             headDuration: headDuration, tailDuration: tailDuration)
    }

    private func streamSampleAges(profile: StreamProfile) -> [Double] {
        let youngest = profile.youngest, oldest = profile.oldest
        let headDuration = profile.headDuration, tailDuration = profile.tailDuration
        var ages = (0...96).map { youngest + (oldest - youngest) * Double($0) / 96 }
        // 開始・終了の細い区間だけサンプルを増やし、長い帯全体の分割数は抑える。
        for i in 0..<12 {
            let offset = rampDuration * Double(i) / 12
            for emittedAt in [offset, pourDuration - offset] {
                let age = time - emittedAt
                if age > youngest && age < oldest { ages.append(age) }
            }
        }
        if headDuration > 0 {
            for i in 0...16 {
                // 角度に等間隔で点を置き、丸い先端近くにも十分な頂点を確保する。
                let theta = Double(i) / 16 * .pi
                ages.append(oldest - headDuration * (1 + cos(theta)) / 2)
            }
        }
        if separatedTailStart != nil && tailDuration > 0 {
            for i in 0..<12 {
                let theta = Double(i) / 12 * .pi / 2
                ages.append(youngest + tailDuration * (1 - cos(theta)))
            }
        }
        return ages.sorted()
    }

    private func streamCrossSection(at age: Double, profile: StreamProfile)
        -> (point: SIMD2<Double>, normal: SIMD2<Double>, halfWidth: Double) {
        // 現在の流量を帯全体に適用せず、その水が投入された時刻の流量を使う。
        // これにより、流量の増減が上流から下流へ伝わる。
        let areaRate = emissionRate(at: min(time, time - age))
        var point = flightPosition(age: age)
        let phase = (time - age) * 29
        // 落下中に育つうねりは描画上の近似。乱流や表面張力を解いてはいない。
        let growth = min(1, max(0, age * 3))
        let wobble = (sin(phase) + 0.4 * sin(phase * 1.73)) * 0.006 * growth * material.streamWobble
        let onWall = point.x <= 0.002 || point.x >= width - 0.002
        let velocity = SIMD2(onWall ? 0 : inletVelocity.x, inletVelocity.y + gravity * max(0, age))
        let speed = simd_length(velocity)
        let normal = SIMD2(velocity.y, -velocity.x) / speed
        // 断面の幅はQ/速度。加速すると細くなる帯に、見た目の太さの変化を重ねる。
        let halfWidth = areaRate / (2 * speed) * (1 + 0.22 * growth * sin(phase * 1.3) * material.streamWobble)
        if !onWall { point += normal * wobble }
        return (point, normal, roundedStreamWidth(halfWidth, at: age, profile: profile))
    }

    private func roundedStreamWidth(_ baseWidth: Double, at age: Double, profile: StreamProfile) -> Double {
        let youngest = profile.youngest, oldest = profile.oldest
        let headDuration = profile.headDuration, headRadius = profile.headRadius
        let tailDuration = profile.tailDuration
        var halfWidth = baseWidth
        if headDuration > 0 {
            // 丸みだけを先端に足すと「針の先の玉」に見えるため、初期の細い部分もつなぐ。
            // 増流区間の後半で補正を滑らかに0へ戻し、通常の流量に基づく幅へ接続する。
            let emittedAt = min(time, time - age)
            let blend = min(1, max(0, (emittedAt - rampDuration / 2) / (rampDuration / 2)))
            let neck = 1 - blend * blend * (3 - 2 * blend)
            halfWidth = max(halfWidth, headRadius * neck)
        }
        if headDuration > 0, age >= oldest - headDuration {
            let progress = min(1, max(0, (age - (oldest - headDuration)) / headDuration))
            let roundWidth = headRadius * sqrt(max(0, 1 - pow(2 * progress - 1, 2)))
            // ふくらみの後半を楕円の輪郭で閉じ、最後の断面は幅0にする。
            halfWidth = progress >= 0.5 ? roundWidth : max(halfWidth, roundWidth)
        }
        if separatedTailStart != nil && tailDuration > 0 && age < youngest + tailDuration {
            let progress = max(0, (age - youngest) / tailDuration)
            halfWidth *= sqrt(max(0, 1 - pow(1 - progress, 2)))
        }
        return halfWidth
    }

    /// 物理座標（m、下向きy）を描画座標（0〜1、上向きy）へ変換する。
    private func normalizedPosition(_ point: SIMD2<Double>) -> SIMD2<Float> {
        SIMD2(Float(point.x / width), Float(1 - point.y / height))
    }
}
