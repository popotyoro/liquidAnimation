import SwiftUI

struct ContentView: View {
    @State private var controls = FluidControls()
    @State private var showsSettings = false

    var body: some View {
        DemoBackground()
        .liquidOverlay(controls: controls, ignoresSafeArea: true)
        .overlay(alignment: .bottom) {
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
        .safeAreaPadding(.bottom, 128)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}


#Preview {
    ContentView()
}
