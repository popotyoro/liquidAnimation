import Foundation

/// 壁で途切れても重みの総和を1に保つ、格子上のガウス分布。
struct GaussianFootprint {
    let columns: ClosedRange<Int>
    private let x: Double
    private let sigma: Double
    private let dx: Double
    private let weightSum: Double

    init(x: Double, column: Int, sigma: Double, dx: Double, columnCount: Int) {
        self.x = x
        self.sigma = sigma
        self.dx = dx
        let radius = Int(ceil(3 * sigma / dx))
        columns = max(0, column - radius)...min(columnCount - 1, column + radius)
        weightSum = columns.reduce(0) { sum, i in
            sum + Self.weight(at: i, x: x, sigma: sigma, dx: dx)
        }
    }

    func normalizedWeight(at column: Int) -> Double {
        Self.weight(at: column, x: x, sigma: sigma, dx: dx) / weightSum
    }

    private static func weight(at column: Int, x: Double, sigma: Double, dx: Double) -> Double {
        exp(-0.5 * pow((Double(column) + 0.5) * dx - x, 2) / (sigma * sigma))
    }
}
