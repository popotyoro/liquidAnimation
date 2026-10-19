import SwiftUI

/// 画面が存在する間は一つの再生状態を保持し、行の再生成では水位を初期化しない。
struct LiquidFillDemoView: View {
    let controls: FluidControls
    let openSettings: () -> Void
    @State private var isFilled = false

    init(controls: FluidControls, openSettings: @escaping () -> Void, initiallyFilled: Bool = false) {
        self.controls = controls
        self.openSettings = openSettings
        _isFilled = State(initialValue: initiallyFilled)
    }

    var body: some View {
        NavigationStack {
            List(LiquidFillSample.examples) { sample in
                LiquidFillRow(sample: sample, fraction: isFilled ? sample.target : 0,
                              color: .liquidFill(for: controls.configuration))
                    .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("行に溜める")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("設定", systemImage: "slider.horizontal.3", action: openSettings)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    HStack {
                        Text(controls.configuration.kind.name)
                        Text("それぞれの目標まで、液体が溜まります。")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        Button("溜める", systemImage: "drop.fill") {
                            withAnimation(.easeInOut(duration: 1.8)) { isFilled = true }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isFilled)
                        Button("空にする", systemImage: "arrow.counterclockwise") {
                            withAnimation(.easeOut(duration: 0.35)) { isFilled = false }
                        }
                        .buttonStyle(.bordered)
                        .disabled(!isFilled)
                    }
                    .controlSize(.large)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.bar)
            }
        }
    }
}
