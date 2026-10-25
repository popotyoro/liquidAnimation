import SwiftUI

/// 日付と量を液体越しに表示する。セル自身に再生状態や更新ループは持たせない。
struct LiquidCalendarCell: View {
    let day: LiquidCalendarDay
    let progress: Double
    let color: Color
    @ScaledMetric(relativeTo: .caption) private var minimumHeight = 76

    var body: some View {
        VStack(spacing: 12) {
            Text(day.number, format: .number)
                .font(.subheadline.weight(.semibold))
            if day.isInMonth {
                Text(day.fraction, format: .percent.precision(.fractionLength(0)))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, minHeight: minimumHeight)
        .background(.background.opacity(day.isInMonth ? 1 : 0.35))
        .liquidFill(fraction: day.fraction * progress, color: color, animationTrigger: progress)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(day.isInMonth ? 1 : 0.35)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(day.date, format: .dateTime.year().month().day()))
        .accessibilityValue(day.isInMonth
            ? Text(day.fraction * progress, format: .percent.precision(.fractionLength(0)))
            : Text("表示月の範囲外"))
    }
}
