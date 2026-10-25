import LiquidFluid
import SwiftUI

struct FluidSettingsView: View {
    @Bindable var controls: FluidControls
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("種類", selection: $controls.configuration.kind) {
                        ForEach(FluidKind.allCases) { kind in
                            Text(kind.name).tag(kind)
                        }
                    }
                    Picker("色", selection: $controls.configuration.color) {
                        ForEach(FluidColorChoice.allCases) { color in
                            Text(color.name).tag(color)
                        }
                    }
                    setting("目標量", value: $controls.configuration.fill, range: 0...1, unit: "%", scale: 100)
                    setting("不透明度", value: $controls.configuration.opacity, range: 0...1, unit: "%", scale: 100)
                } header: {
                    Text("液体")
                } footer: {
                    Text("注ぐ画面の種類は次に「注ぐ」を押すと反映します。カレンダー画面の配色と、色・不透明度はすぐに反映します。")
                }
                Section {
                    setting("注ぐ位置", value: $controls.configuration.sourcePosition,
                            range: 0.15...0.85, unit: "%", scale: 100)
                    setting("注ぐ角度", value: $controls.configuration.angle,
                            range: -65...65, unit: "°")
                    setting("流量", value: $controls.configuration.flow,
                            range: 0.02...0.16, unit: "% / 秒", scale: 100)
                } header: {
                    Text("注ぎ方")
                } footer: {
                    Text("「注ぐ」は現在の設定で空から開始します。「10%追加」は現在の液体と注ぎ方を保って追加します。角度は下向きが 0°、正の値で右向きです。")
                }
                Section {
                    Toggle("注水に合わせて振動する", isOn: $controls.isHapticFeedbackEnabled)
                } header: {
                    Text("触覚フィードバック")
                } footer: {
                    Text("注水開始・初回着水・目標到達時に触覚を返します。")
                }

            }
            .navigationTitle("液体の設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } } }
        }
    }

    private func setting(_ title: LocalizedStringKey, value: Binding<Double>, range: ClosedRange<Double>,
                         unit: String, scale: Double = 1) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value.wrappedValue * scale, specifier: "%.0f") \(unit)")
                    .foregroundStyle(.secondary).monospacedDigit()
            }
            Slider(value: value, in: range) { Text(title) }
                .accessibilityValue("\(value.wrappedValue * scale, specifier: "%.0f") \(unit)")
        }
    }
}
