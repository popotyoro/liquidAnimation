import SwiftUI

/// 計測値だけを監視し、その変更による再評価をこのViewに閉じ込める。
struct FluidMetricsView: View {
    let controls: FluidControls

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                metric("描画", value: "\(controls.framesPerSecond, specifier: "%.0f") fps")
                metric("GPU", value: "\(controls.gpuMilliseconds, specifier: "%.1f") ms")
                metric("CPU", value: "\(controls.simulationMilliseconds, specifier: "%.1f") ms")
            }
            VStack(alignment: .leading, spacing: 4) {
                metric("描画", value: "\(controls.framesPerSecond, specifier: "%.0f") fps")
                metric("GPU", value: "\(controls.gpuMilliseconds, specifier: "%.1f") ms")
                metric("CPU", value: "\(controls.simulationMilliseconds, specifier: "%.1f") ms")
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metric(_ title: LocalizedStringKey, value: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            Text(title)
            Text(value)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}
