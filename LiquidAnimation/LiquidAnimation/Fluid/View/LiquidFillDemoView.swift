import SwiftUI

/// 月間カレンダーへ軽量な水位表示を適用する。表示月と再生状態は画面側で保持する。
struct LiquidFillDemoView: View {
    let controls: FluidControls
    let openSettings: () -> Void
    @State private var isFilled: Bool
    @State private var month: LiquidCalendarMonth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    init(controls: FluidControls, openSettings: @escaping () -> Void, initiallyFilled: Bool = false,
         date: Date = .now, calendar: Calendar = .current) {
        self.controls = controls
        self.openSettings = openSettings
        _isFilled = State(initialValue: initiallyFilled)
        _month = State(initialValue: LiquidCalendarMonth(containing: date, calendar: calendar))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    monthNavigation
                    HStack(spacing: 6) {
                        ForEach(month.days.prefix(7)) { day in
                            Text(day.date, format: .dateTime.weekday(.abbreviated))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(month.days) { day in
                            LiquidCalendarCell(day: day, progress: isFilled ? 1 : 0,
                                               color: .liquidFill(for: controls.configuration))
                        }
                    }
                    Text("日ごとの目標達成率を表したサンプルデータです。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16).padding(.vertical)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("飲んだ量カレンダー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("設定", systemImage: "slider.horizontal.3", action: openSettings)
                }
            }
            .safeAreaInset(edge: .bottom) { playbackControls }
        }
    }

    private var monthNavigation: some View {
        HStack {
            Button("前の月", systemImage: "chevron.left") { month = month.shifted(by: -1) }
                .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
            Spacer()
            Text(month.start, format: .dateTime.year().month(.wide))
                .font(.title3.bold()).accessibilityAddTraits(.isHeader)
            Spacer()
            Button("次の月", systemImage: "chevron.right") { month = month.shifted(by: 1) }
                .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
        }
    }

    private var playbackControls: some View {
        VStack(spacing: 12) {
            Text("\(controls.configuration.kind.name) · 日ごとの量を表示")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Button("溜める", systemImage: "drop.fill") {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 1.8)) { isFilled = true }
                }
                .buttonStyle(.borderedProminent).disabled(isFilled)
                Button("空にする", systemImage: "arrow.counterclockwise") {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.35)) { isFilled = false }
                }
                .buttonStyle(.bordered).disabled(!isFilled)
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity).padding().background(.bar)
    }
}
