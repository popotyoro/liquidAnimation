import Foundation

/// 種類とは独立した色の選択。standardだけが、注水中の種類の標準色に従う。
public nonisolated enum FluidColorChoice: String, CaseIterable, Identifiable, Sendable {
    case standard, blue, amber, green, pink

    public var id: String { rawValue }

    func palette(for kind: FluidKind) -> FluidPalette {
        switch self {
        case .standard: kind == .beer ? .amber : .blue
        case .blue: .blue
        case .amber: .amber
        case .green: .green
        case .pink: .pink
        }
    }
}
