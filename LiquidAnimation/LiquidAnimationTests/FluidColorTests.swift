import Testing
@testable import LiquidAnimation

struct FluidColorTests {
    @Test("標準色はビールを琥珀色にし水をブルーにする")
    func standardColorFollowsKind() {
        #expect(FluidColorChoice.standard.palette(for: .beer) == .amber)
        #expect(FluidColorChoice.standard.palette(for: .water) == .blue)
    }

    @Test("明示的に選んだ色は液体の種類を変えても保持する", arguments: FluidKind.allCases)
    func explicitColorOverridesKind(kind: FluidKind) {
        #expect(FluidColorChoice.pink.palette(for: kind) == .pink)
    }

    @Test("設定の数値補正は選択した種類と色を変えない")
    func sanitizationPreservesKindAndColor() {
        var configuration = FluidConfiguration()
        configuration.kind = .beer
        configuration.color = .green
        configuration.fill = .nan

        let actual = configuration.sanitized

        #expect(actual.kind == .beer)
        #expect(actual.color == .green)
        #expect(actual.fill == 0.5)
    }
}
