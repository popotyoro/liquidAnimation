import LiquidFluid
import SwiftUI

/// 注水の操作と、動作中に確認する計測値をまとめる。
struct FluidControlBar: View {
    let controls: FluidControls
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
            HStack(spacing: 16) {
                Button("25%を表示", systemImage: "drop") { controls.show(fraction: 0.25) }
                Button("10%追加", systemImage: "plus") { controls.pour(to: controls.targetFraction + 0.1) }
                    .disabled(controls.targetFraction >= 1)
            }
            .buttonStyle(.bordered)
            Divider()
            FluidMetricsView(controls: controls)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .sensoryFeedback(trigger: controls.feedback) { _, feedback in
            guard controls.isHapticFeedbackEnabled else { return nil }
            switch feedback {
            case .started, .firstContact: return .impact(weight: .light, intensity: 0.35)
            case .completed: return .success
            case nil: return nil
            }
        }
    }
}
