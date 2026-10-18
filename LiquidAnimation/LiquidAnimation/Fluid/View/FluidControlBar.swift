import SwiftUI

/// 注水の操作と、動作中に確認する計測値をまとめる。
struct FluidControlBar: View {
    @Bindable var controls: FluidControls
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(controls.isPaused ? "一時停止中" : controls.status).font(.caption)
                Spacer()
                Text("投入 \(controls.insertedFraction, format: .percent.precision(.fractionLength(0)))")
                    .font(.caption.monospacedDigit())
            }
            HStack(spacing: 12) {
                Button("注ぐ", systemImage: "drop.fill") { controls.pour() }
                    .buttonStyle(.borderedProminent)
                Button(controls.isPaused ? "再開" : "一時停止",
                       systemImage: controls.isPaused ? "play.fill" : "pause.fill") {
                    controls.isPaused.toggle()
                }
                .labelStyle(.iconOnly)
                Button("空にする", systemImage: "arrow.counterclockwise") { controls.reset() }
                    .labelStyle(.iconOnly)
                Spacer(minLength: 0)
                Button("設定", systemImage: "slider.horizontal.3", action: openSettings)
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            Divider()
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
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
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
