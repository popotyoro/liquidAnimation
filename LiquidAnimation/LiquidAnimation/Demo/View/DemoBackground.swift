import LiquidFluid
import SwiftUI

struct DemoBackground: View {
    let kind: FluidKind
    @State private var count = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack {
                    Label("LIQUID LAB", systemImage: "drop")
                        .font(.caption.weight(.semibold)).tracking(3)
                    Spacer()
                    Text(kind.name).font(.caption)
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
        .safeAreaPadding(.bottom, 176)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}
