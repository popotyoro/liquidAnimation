// CPU上の物理モデルと、Metalへ渡す描画データの作成を担当する。
import Foundation
import Metal
import simd

/// Fluid.metalの同名構造体とフィールド順序・型・サイズを一致させる。
nonisolated struct WaterVertex: Sendable {
    var position: SIMD2<Float> // 描画領域で正規化した位置。左下が(0, 0)。
    var texture: SIMD2<Float> // 水流では横断方向、飛沫では楕円の局所座標として使う。
}

/// 各描画パスで共用する定数。Metal側とのメモリ配置を揃える。
nonisolated struct WaterUniforms: Sendable {
    var viewport: SIMD4<Float> // ピクセル幅・高さ、不透明度、水面の列数。
}

/// Metalの初期化・描画に失敗した理由を操作画面へ伝える。
nonisolated enum FluidError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? {
        switch self { case .unavailable(let message): message }
    }
}

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
    private var parcels: [Parcel] = []
    static let maximumDrops = 96
    /// 独立した飛沫。水面へ戻ったら吸収し、再び跳ねさせない。
    private struct Drop {
        var position: SIMD2<Double> // 単位はm、yは下向き。描画座標と上下が逆。
        var velocity: SIMD2<Double>
        var area: Double
    }
    private var drops: [Drop] = []
    private var lastSplashTime = -1.0
    private var splashSequence = 0
    var splashCount: Int { drops.count }
    var splashFraction: Double { drops.reduce(0) { $0 + $1.area } / capacity }
    var jetFraction: Double { parcels.reduce(0) { $0 + $1.area } / capacity }
    private var targetArea = 0.0
    private let gravity = 9.81
    private let inletSpeed = 1.6
    private let dryDepth = 1e-7

    /// 水流を時間区間ごとの面積で記録する。丸い粒として描くためのデータではない。
    private struct Parcel {
        var time: Double
        var area: Double
    }

    private var nominalRate: Double { configuration.flow * capacity }
    // 少量指定では増減区間を短くし、最大流量のまま流す区間を省く。
    private var rampDuration: Double { min(0.25, targetArea / nominalRate) }
    var pourDuration: Double { targetArea > 0 ? targetArea / nominalRate + rampDuration : 0 }
    var inletRate: Double { emissionRate(at: time) }

    /// smoothstepで流量を滑らかに増減する。描画にも投入時刻ごとの値を使う。
    private func emissionRate(at instant: Double) -> Double {
        guard rampDuration > 0, instant > 0, instant < pourDuration else { return 0 }
        let u = min(1, instant / rampDuration, (pourDuration - instant) / rampDuration)
        return nominalRate * u * u * (3 - 2 * u)
    }

    /// 流量の解析的な積分。増減する流量を単純加算する誤差を避け、目標量に合わせる。
    private func cumulativeEmission(at instant: Double) -> Double {
        guard rampDuration > 0, instant > 0 else { return 0 }
        if instant >= pourDuration { return targetArea }
        func rampIntegral(_ u: Double) -> Double { u * u * u * (1 - 0.5 * u) }
        if instant < rampDuration {
            return nominalRate * rampDuration * rampIntegral(instant / rampDuration)
        }
        if instant > pourDuration - rampDuration {
            return targetArea - nominalRate * rampDuration * rampIntegral((pourDuration - instant) / rampDuration)
        }
        return nominalRate * (instant - rampDuration / 2)
    }

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
        targetArea = start ? self.configuration.fill * capacity : 0
        emittedArea = 0
        landedArea = 0
        time = 0
        parcels.removeAll(keepingCapacity: true)
        drops.removeAll(keepingCapacity: true)
        lastSplashTime = -1
        splashSequence = 0
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
            var maxSpeed = 0.1
            for i in depths.indices {
                let velocity = depths[i] > dryDepth ? abs(momentum[i] / depths[i]) : 0
                maxSpeed = max(maxSpeed, velocity + sqrt(gravity * depths[i]))
            }
            // 波の伝播速度と流速に対して、1ステップでセルを飛び越えない刻みを選ぶ。
            let dt = min(remaining, 1.0 / 240, 0.4 * dx / maxSpeed)
            time += dt
            if isPouring {
                // 増減する流量を積分し、その時刻までに投入すべき総量との差分だけを加える。
                // 水流の各区間の代表時刻は、時間刻みの中央に置く。
                let amount = min(max(0, cumulativeEmission(at: time) - emittedArea), targetArea - emittedArea)
                emittedArea += amount
                if amount > 0 { parcels.append(Parcel(time: min(time - dt / 2, pourDuration), area: amount)) }
            }
            // 飛沫を戻す → 水流を着水させる → 圧力を更新 → 水面を進める、の順で処理する。
            advanceDrops(dt: dt)
            for i in impactImpulse.indices { impactImpulse[i] = 0 }
            depositArrivals()
            updateImpactPressure(dt: dt)
            solveShallowWater(dt: dt)
            remaining -= dt
        }
        preserveVolume()
    }

    /// 初速と重力から水流の中心軌道を求める。壁ではxを固定して下へ流す。
    /// 負のageは入口を画面外へ延ばす描画用で、上流へ直線的に延長する。
    private func flightPosition(age: Double) -> SIMD2<Double> {
        let x = configuration.sourcePosition * width + inletSpeed * sin(angle) * age
        let y = inletSpeed * cos(angle) * age + 0.5 * gravity * max(0, age) * max(0, age)
        return SIMD2(min(max(x, 0.002), width - 0.002), y)
    }

    /// 水面に達した区間を水流から取り除き、水面と飛沫へ面積を振り分ける。
    private func depositArrivals() {
        var survivors: [Parcel] = []
        survivors.reserveCapacity(parcels.count)
        for parcel in parcels {
            let age = time - parcel.time
            let point = flightPosition(age: age)
            let column = min(columnCount - 1, max(0, Int(point.x / dx)))
            if point.y < height - depths[column] {
                survivors.append(parcel)
                continue
            }
            let impactSpeed = inletSpeed * cos(angle) + gravity * age
            // 着水量の一部だけを飛沫へ回し、水を増やさない。
            // 発生間隔・同時数・上昇速度を制限して、負荷と過剰な跳ね返りを抑える。
            var splashArea = 0.0
            if depths[column] > 0.008, height - depths[column] > 0.025,
               time - lastSplashTime > 0.025, drops.count + 2 <= Self.maximumDrops {
                splashArea = parcel.area * 0.32
                lastSplashTime = time
                splashSequence += 1
                for side in [-1.0, 1.0] {
                    let variation = 0.8 + 0.2 * sin(Double(splashSequence) * 2.4 + side)
                    let rise = min(1.15, impactSpeed * 0.28) * variation
                    let offset = configuration.flow * capacity / impactSpeed * 0.6 + dx
                    let x = min(width - 0.002, max(0.002, point.x + side * offset))
                    let launchColumn = min(columnCount - 1, max(0, Int(x / dx)))
                    let position = SIMD2(x, max(0, height - depths[launchColumn] - 0.012))
                    drops.append(Drop(position: position,
                        velocity: SIMD2(side * rise * 0.8 + inletSpeed * sin(angle) * 0.15, -rise),
                        area: splashArea / 2))
                }
            }
            // 鉛直方向の衝撃をガウス分布で周囲へ配る。
            // 分布に数セルの幅を持たせ、着水点のへこみを格子上で解像できるようにする。
            let sigma = max(2.5 * dx, configuration.flow * capacity / impactSpeed * 0.65)
            let radius = Int(ceil(3 * sigma / dx))
            let impactLower = max(0, column - radius), impactUpper = min(columnCount - 1, column + radius)
            // 壁際で分布が途切れても、重みの総和を1に保つ。
            var pressureWeight = 0.0
            for i in impactLower...impactUpper {
                pressureWeight += exp(-0.5 * pow((Double(i) + 0.5) * dx - point.x, 2) / (sigma * sigma))
            }
            for i in impactLower...impactUpper {
                let weight = exp(-0.5 * pow((Double(i) + 0.5) * dx - point.x, 2) / (sigma * sigma)) / pressureWeight
                impactImpulse[i] += parcel.area * impactSpeed * weight / dx
            }
            // 飛沫へ回した分を除き、残りを局所的な水深へ変換する。
            let deposited = parcel.area - splashArea
            landedArea += deposited
            let lower = max(0, column - 3), upper = min(columnCount - 1, column + 3)
            var sum = 0.0
            for i in lower...upper { sum += exp(-0.5 * pow(Double(i - column) / 1.5, 2)) }
            let horizontal = inletSpeed * sin(angle)
            for i in lower...upper {
                let weight = exp(-0.5 * pow(Double(i - column) / 1.5, 2)) / sum
                let addedDepth = deposited * weight / dx
                depths[i] += addedDepth
                // 着水の横への広がりを近似する運動量。水の量は増やさない。
                let outward = 0.30 * impactSpeed * tanh(Double(i - column))
                momentum[i] += addedDepth * (horizontal * 0.35 + outward)
            }
        }
        parcels = survivors
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
                vertices.append(WaterVertex(position: SIMD2(Float(point.x / width), Float(1 - point.y / height)),
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
            let target = min(gravity * 0.06, 0.12 * impactImpulse[i] / dt)
            impactPressure[i] += (target - impactPressure[i]) * response
        }
    }

    /// 水深hと水平流量q=huを有限体積法で更新する。圧力勾配は運動量だけに作用する。
    private func solveShallowWater(dt: Double) {
        // Rusanov流束 F=(hu, hu²/h + gh²/2) を列境界で計算する。
        // 両端では仮想セルの流量の符号を反転し、壁を通る水量を0にする。
        for face in 0...columnCount {
            let left = max(0, face - 1), right = min(columnCount - 1, face)
            let hL = depths[left], hR = depths[right]
            let qL = face == 0 ? -momentum[left] : momentum[left]
            let qR = face == columnCount ? -momentum[right] : momentum[right]
            let uL = hL > dryDepth ? qL / hL : 0
            let uR = hR > dryDepth ? qR / hR : 0
            let speed = max(abs(uL) + sqrt(gravity * hL), abs(uR) + sqrt(gravity * hR))
            heightFlux[face] = 0.5 * (qL + qR) - 0.5 * speed * (hR - hL)
            momentumFlux[face] = 0.5 * (qL * uL + qR * uR + 0.5 * gravity * (hL*hL + hR*hR))
                - 0.5 * speed * (qR - qL)
        }
        let ratio = dt / dx
        // 指数減衰は時間刻みを変えても同じ時間あたりの減衰率になる。
        let drag = exp(-2.8 * dt)
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
        var low = -max(height, depths.max() ?? 0), high = height
        for _ in 0..<44 {
            let shift = (low + high) / 2
            let sum = depths.reduce(0) { $0 + min(height, max(0, $1 + shift)) }
            if sum < desiredSum { low = shift } else { high = shift }
        }
        let shift = (low + high) / 2
        for i in depths.indices {
            let old = depths[i]
            depths[i] = min(height, max(0, old + shift))
            if depths[i] < dryDepth { momentum[i] = 0 }
            else if old > dryDepth { momentum[i] *= min(1, depths[i] / old) }
        }
    }

    // 基本97断面 + 増減区間の最大24断面。それぞれ左右の2頂点を持つ。
    static let maximumStreamVertices = 242

    /// 投入時刻ごとの流量から水流の帯を作る。物理モデルの水量は変更しない。
    func streamVertices() -> [WaterVertex] {
        guard let first = parcels.first else { return [] }
        // 角度が大きい場合も入口の切断面が画面内に見えないよう、上流を画面外へ延ばす。
        let inletExtension = -(nominalRate / inletSpeed + 0.02) / (inletSpeed * cos(angle))
        let youngest = isPouring ? inletExtension : max(0, time - pourDuration)
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
        var vertices: [WaterVertex] = []
        vertices.reserveCapacity(Self.maximumStreamVertices)
        var ages = (0...96).map { youngest + (oldest - youngest) * Double($0) / 96 }
        // 開始・終了の細い区間だけサンプルを増やし、長い帯全体の分割数は抑える。
        for i in 0..<12 {
            let offset = rampDuration * Double(i) / 12
            for emittedAt in [offset, pourDuration - offset] {
                let age = time - emittedAt
                if age > youngest && age < oldest { ages.append(age) }
            }
        }
        ages.sort()
        for (index, age) in ages.enumerated() {
            // 現在の流量を帯全体に適用せず、その水が投入された時刻の流量を使う。
            // これにより、流量の増減が上流から下流へ伝わる。
            let areaRate = emissionRate(at: min(time, time - age))
            var point = flightPosition(age: age)
            let phase = (time - age) * 29
            // 落下中に育つうねりは描画上の近似。乱流や表面張力を解いてはいない。
            let growth = min(1, max(0, age * 3))
            let wobble = (sin(phase) + 0.4 * sin(phase * 1.73)) * 0.006 * growth
            let onWall = point.x <= 0.002 || point.x >= width - 0.002
            let velocity = SIMD2(onWall ? 0 : inletSpeed * sin(angle), inletSpeed * cos(angle) + gravity * max(0, age))
            let speed = simd_length(velocity)
            let normal = SIMD2(velocity.y, -velocity.x) / speed
            // 断面の幅はQ/速度。加速すると細くなる帯に、見た目の太さの変化を重ねる。
            let halfWidth = areaRate / (2 * speed) * (1 + 0.22 * growth * sin(phase * 1.3))
            if !onWall { point += normal * wobble }
            for side in [-1.0, 1.0] {
                let edge = point + side * halfWidth * normal
                vertices.append(WaterVertex(position: SIMD2(Float(edge.x / width), Float(1 - edge.y / height)),
                                            texture: SIMD2(Float(side), Float(index) / Float(ages.count - 1))))
            }
        }
        return vertices
    }
}

/// 物理モデルと、GPUが読む共有メモリを所有する。
/// WaterModelがDoubleで計算した結果を、描画用のFloatへ変換する。
final class FluidSimulation {
    let model: WaterModel
    let surfaceBuffer: any MTLBuffer
    let streamBuffer: any MTLBuffer
    let splashBuffer: any MTLBuffer
    private(set) var splashVertexCount = 0
    private(set) var streamVertexCount = 0

    init(device: any MTLDevice, aspectRatio: Double) throws {
        model = WaterModel(aspectRatio: aspectRatio)
        guard let surface = device.makeBuffer(length: model.columnCount * MemoryLayout<Float>.stride,
                                              options: .storageModeShared),
              let stream = device.makeBuffer(length: WaterModel.maximumStreamVertices * MemoryLayout<WaterVertex>.stride,
                                             options: .storageModeShared),
              let splash = device.makeBuffer(length: WaterModel.maximumDrops * 6 * MemoryLayout<WaterVertex>.stride,
                                             options: .storageModeShared) else {
            throw FluidError.unavailable("水面の描画メモリを確保できませんでした。")
        }
        surfaceBuffer = surface
        streamBuffer = stream
        splashBuffer = splash
    }

    /// CPU上の最新状態を共有バッファへ転送する。
    /// 呼び出し側は、前フレームのGPU使用が完了した後にだけ書き換えること。
    func uploadSurface() {
        let heights = surfaceBuffer.contents().bindMemory(to: Float.self, capacity: model.columnCount)
        for i in model.depths.indices { heights[i] = Float(model.depths[i] / model.height) }
        let spray = model.splashVertices()
        splashVertexCount = spray.count
        spray.withUnsafeBytes { bytes in
            if let base = bytes.baseAddress, !bytes.isEmpty {
                memcpy(splashBuffer.contents(), base, bytes.count)
            }
        }
        let vertices = model.streamVertices()
        streamVertexCount = vertices.count
        vertices.withUnsafeBytes { bytes in
            if let base = bytes.baseAddress, !bytes.isEmpty {
                memcpy(streamBuffer.contents(), base, bytes.count)
            }
        }
    }
}
