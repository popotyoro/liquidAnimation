import SwiftUI

/// 行は再生状態を所有せず、画面側から渡された水位だけを描く。
struct LiquidFillRow: View {
    let sample: LiquidFillSample
    let fraction: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("サンプル \(sample.id + 1)").font(.headline)
                Spacer()
                Text("目標 \(sample.target, format: .percent.precision(.fractionLength(0)))")
                    .font(.subheadline.monospacedDigit())
            }
            Text("下から、ゆっくり満たす。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .background(.background)
        .liquidFill(fraction: fraction, color: color)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}
