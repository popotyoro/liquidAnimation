import SwiftUI

struct ContentView: View {
    @State private var controls = FluidControls()
    @State private var showsSettings = false

    var body: some View {
        ZStack {
            DemoBackground()
            LiquidOverlay(controls: controls)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .safeAreaInset(edge: .bottom) {
            controlBar.padding(.horizontal).padding(.bottom, 8)
        }
        .sheet(isPresented: $showsSettings) {
            FluidSettingsView(controls: controls)
                .presentationDetents([.medium, .large])
        }
        .alert("液体の計算を続けられません", isPresented: Binding(
            get: { controls.error != nil },
            set: { if !$0 { controls.error = nil; controls.reset() } }
        )) {
            Button("リセット") { controls.error = nil; controls.reset() }
        } message: {
            Text(controls.error ?? "")
        }
    }

    private var controlBar: some View {
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
                Button("設定", systemImage: "slider.horizontal.3") { showsSettings = true }
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
    }
}

private struct DemoBackground: View {
    @State private var count = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack {
                    Label("LIQUID LAB", systemImage: "drop")
                        .font(.caption.weight(.semibold)).tracking(3)
                    Spacer()
                    Text("01 / WATER").font(.caption.monospaced())
                }
                Text("画面を、\n水で満たす。")
                    .font(.largeTitle.bold())
                Text("上から注がれた水が、落ちて、広がって、揺れる。\nこの画面の上に液体を重ねています。")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 16) {
                    RoundedRectangle(cornerRadius: 30).fill(.orange.gradient)
                        .overlay { Image(systemName: "sun.max.fill").font(.largeTitle).foregroundStyle(.white) }
                    Circle().fill(.indigo.gradient)
                        .overlay { Image(systemName: "moon.stars.fill").font(.largeTitle).foregroundStyle(.white) }
                }
                .frame(height: 140)
                VStack(alignment: .leading, spacing: 16) {
                    Text("水の向こうにも、いつもの画面。").font(.headline)
                    Text("文字や図形にぶつからず、左右の壁と底に沿って水がたまります。")
                        .foregroundStyle(.secondary)
                    Button("背景のボタン · \(count)", systemImage: "hand.tap") { count += 1 }
                        .buttonStyle(.bordered)
                    Text("液体越しにも操作できます。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 24))
                HStack {
                    ForEach(0..<5) { index in
                        Text(String(format: "%02d", index + 1))
                            .font(.title3.monospaced()).frame(maxWidth: .infinity)
                    }
                }
                .foregroundStyle(.secondary)
            }
            .padding(24).padding(.top, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

private struct FluidSettingsView: View {
    @Bindable var controls: FluidControls
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("液体") {
                    setting("目標量", value: $controls.configuration.fill, range: 0...1, unit: "%", scale: 100)
                    setting("不透明度", value: $controls.configuration.opacity, range: 0...1, unit: "%", scale: 100)
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
                    Text("不透明度はすぐに反映します。それ以外は次に「注ぐ」を押すと反映し、空の状態から開始します。角度は下向きが 0°、正の値で右向きです。")
                }
                Section("計測") {
                    LabeledContent("描画頻度", value: String(format: "%.0f fps", controls.framesPerSecond))
                    LabeledContent("GPU 時間", value: String(format: "%.1f ms", controls.gpuMilliseconds))
                    Text("60fps は目標値です。性能の判断には実機での測定が必要です。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("液体の設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } } }
        }
    }

    private func setting(_ title: String, value: Binding<Double>, range: ClosedRange<Double>,
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

#Preview {
    ContentView()
}
