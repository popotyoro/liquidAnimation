import Testing
@testable import LiquidAnimation

/// 設定と配色は各ケースのローカル値で、後始末は値の破棄で完了する。
struct FluidColorTests {
    @Test("ビールの標準色は琥珀色になる")
    func beerUsesAmberByDefault() {
        // 準備
        let choice = FluidColorChoice.standard

        // 実行
        let palette = choice.palette(for: .beer)

        // 検証
        #expect(palette == .amber)
    }

    @Test("水の標準色はブルーになる")
    func waterUsesBlueByDefault() {
        // 準備
        let choice = FluidColorChoice.standard

        // 実行
        let palette = choice.palette(for: .water)

        // 検証
        #expect(palette == .blue)
    }

    @Test("明示的に選んだピンクはどの液体の種類でも優先される", arguments: FluidKind.allCases)
    func explicitColorOverridesKind(kind: FluidKind) {
        // 準備
        let choice = FluidColorChoice.pink

        // 実行
        let palette = choice.palette(for: kind)

        // 検証
        #expect(palette == .pink)
    }

    @Test("非有限の液量を補正しても選択した種類と色を保持する")
    func sanitizationPreservesKindAndColor() {
        // 準備
        var configuration = FluidConfiguration()
        configuration.kind = .beer
        configuration.color = .green
        configuration.fill = .nan

        // 実行
        let actual = configuration.sanitized

        // 検証
        #expect(actual.kind == .beer)
        #expect(actual.color == .green)
    }
}
