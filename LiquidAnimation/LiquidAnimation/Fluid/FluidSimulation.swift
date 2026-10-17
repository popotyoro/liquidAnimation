import Foundation
import Metal
import simd

struct WaterVertex {
    var position: SIMD2<Float>
    var texture: SIMD2<Float>
}

struct WaterUniforms {
    var viewport: SIMD4<Float> // pixel width, pixel height, opacity, surface sample count
}

enum FluidError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? {
        switch self { case .unavailable(let message): message }
    }
}

/// A finite-volume shallow-water cross-section plus a volume ledger for the falling jet.
/// Heights and momentum use meters and square meters per second, respectively.
@MainActor
final class WaterModel {
    let columnCount: Int
    let width = 0.75
    let height: Double
    private(set) var depths: [Double]
    private var momentum: [Double]
    private var heightFlux: [Double]
    private var momentumFlux: [Double]
    private(set) var configuration = FluidConfiguration()
    private(set) var emittedArea = 0.0
    private(set) var landedArea = 0.0
    private(set) var time = 0.0
    private var parcels: [Parcel] = []
    private var targetArea = 0.0
    private let gravity = 9.81
    private let inletSpeed = 1.6
    private let dryDepth = 1e-7

    private struct Parcel {
        var time: Double
        var area: Double
    }

    var capacity: Double { width * height }
    var fraction: Double { emittedArea / capacity }
    var landedFraction: Double { landedArea / capacity }
    var airborneFraction: Double { max(0, emittedArea - landedArea) / capacity }
    var isPouring: Bool { emittedArea < targetArea - 1e-12 }
    var hasWater: Bool { emittedArea > 0 }
    var meanDepth: Double { depths.reduce(0, +) / Double(columnCount) }
    var surfaceRange: Double { (depths.max() ?? 0) - (depths.min() ?? 0) }
    var kineticEnergy: Double {
        zip(depths, momentum).reduce(0) { sum, value in
            sum + (value.0 > dryDepth ? value.1 * value.1 / (2 * value.0) : 0)
        } * dx
    }
    private var dx: Double { width / Double(columnCount) }
    private var angle: Double { configuration.angle * .pi / 180 }

    init(aspectRatio: Double, columnCount: Int = 128) {
        self.columnCount = max(16, columnCount)
        height = width * min(4, max(0.5, aspectRatio))
        depths = .init(repeating: 0, count: self.columnCount)
        momentum = depths
        heightFlux = .init(repeating: 0, count: self.columnCount + 1)
        momentumFlux = heightFlux
    }

    func reset(configuration: FluidConfiguration, start: Bool) {
        self.configuration = configuration.sanitized
        targetArea = start ? self.configuration.fill * capacity : 0
        emittedArea = 0
        landedArea = 0
        time = 0
        parcels.removeAll(keepingCapacity: true)
        for i in depths.indices { depths[i] = 0; momentum[i] = 0 }
    }

    func advance(by duration: Double) {
        guard duration.isFinite, duration > 0 else { return }
        var remaining = min(duration, 1.0 / 30)
        while remaining > 1e-9 {
            var maxSpeed = 0.1
            for i in depths.indices {
                let velocity = depths[i] > dryDepth ? abs(momentum[i] / depths[i]) : 0
                maxSpeed = max(maxSpeed, velocity + sqrt(gravity * depths[i]))
            }
            let dt = min(remaining, 1.0 / 240, 0.4 * dx / maxSpeed)
            time += dt
            if isPouring {
                let amount = min(configuration.flow * capacity * dt, targetArea - emittedArea)
                emittedArea += amount
                parcels.append(Parcel(time: time, area: amount))
            }
            depositArrivals()
            solveShallowWater(dt: dt)
            remaining -= dt
        }
        preserveVolume()
    }

    private func flightPosition(age: Double) -> SIMD2<Double> {
        let x = configuration.sourcePosition * width + inletSpeed * sin(angle) * age
        let y = inletSpeed * cos(angle) * age + 0.5 * gravity * age * age
        return SIMD2(min(max(x, 0.002), width - 0.002), y)
    }

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
            landedArea += parcel.area
            let lower = max(0, column - 3), upper = min(columnCount - 1, column + 3)
            var sum = 0.0
            for i in lower...upper { sum += exp(-0.5 * pow(Double(i - column) / 1.5, 2)) }
            let horizontal = inletSpeed * sin(angle)
            let impactSpeed = inletSpeed * cos(angle) + gravity * age
            for i in lower...upper {
                let weight = exp(-0.5 * pow(Double(i - column) / 1.5, 2)) / sum
                let addedDepth = parcel.area * weight / dx
                depths[i] += addedDepth
                // A small outward impulse represents vertical impact; it adds no volume.
                let outward = 0.12 * impactSpeed * tanh(Double(i - column))
                momentum[i] += addedDepth * (horizontal * 0.35 + outward)
            }
        }
        parcels = survivors
    }

    private func solveShallowWater(dt: Double) {
        // Rusanov flux for (h, hu): F = (hu, hu²/h + g h²/2).
        // Reflecting ghost cells make the mass flux at each wall exactly zero.
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
        let drag = exp(-2.8 * dt)
        for i in depths.indices {
            depths[i] = max(0, depths[i] - ratio * (heightFlux[i + 1] - heightFlux[i]))
            momentum[i] = (momentum[i] - ratio * (momentumFlux[i + 1] - momentumFlux[i])) * drag
            if depths[i] <= dryDepth { momentum[i] = 0 }
            else { momentum[i] = min(max(momentum[i], -2.5 * depths[i]), 2.5 * depths[i]) }
        }
    }

    private func preserveVolume() {
        // A bounded constant shift removes round-off/clipping errors, preserving wave shape.
        // This also prevents waves at 100% from extending beyond the closed rectangular tank.
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

    func streamVertices() -> [WaterVertex] {
        guard let first = parcels.first, let last = parcels.last else { return [] }
        let youngest = max(0, time - last.time)
        let oldest = time - first.time
        let areaRate = configuration.flow * capacity
        var vertices: [WaterVertex] = []
        for i in 0...96 {
            let age = youngest + (oldest - youngest) * Double(i) / 96
            let point = flightPosition(age: age)
            let onWall = point.x <= 0.002 || point.x >= width - 0.002
            let velocity = SIMD2(onWall ? 0 : inletSpeed * sin(angle), inletSpeed * cos(angle) + gravity * age)
            let speed = simd_length(velocity)
            let normal = SIMD2(velocity.y, -velocity.x) / speed
            let halfWidth = areaRate / (2 * speed)
            for side in [-1.0, 1.0] {
                let edge = point + side * halfWidth * normal
                vertices.append(WaterVertex(position: SIMD2(Float(edge.x / width), Float(1 - edge.y / height)),
                                            texture: SIMD2(Float(side), Float(i) / 96)))
            }
        }
        return vertices
    }
}

@MainActor
final class FluidSimulation {
    let model: WaterModel
    let surfaceBuffer: any MTLBuffer
    let streamBuffer: any MTLBuffer
    private(set) var streamVertexCount = 0

    init(device: any MTLDevice, aspectRatio: Double) throws {
        model = WaterModel(aspectRatio: aspectRatio)
        guard let surface = device.makeBuffer(length: model.columnCount * MemoryLayout<Float>.stride,
                                              options: .storageModeShared),
              let stream = device.makeBuffer(length: 194 * MemoryLayout<WaterVertex>.stride,
                                             options: .storageModeShared) else {
            throw FluidError.unavailable("水面の描画メモリを確保できませんでした。")
        }
        surfaceBuffer = surface
        streamBuffer = stream
    }

    func uploadSurface() {
        let heights = surfaceBuffer.contents().bindMemory(to: Float.self, capacity: model.columnCount)
        for i in model.depths.indices { heights[i] = Float(model.depths[i] / model.height) }
        let vertices = model.streamVertices()
        streamVertexCount = vertices.count
        vertices.withUnsafeBytes { bytes in
            if let base = bytes.baseAddress, !bytes.isEmpty {
                memcpy(streamBuffer.contents(), base, bytes.count)
            }
        }
    }
}
