import Foundation
import LiquidFluid

extension FluidColorChoice {
    var name: LocalizedStringResource {
        switch self {
        case .standard: "種類の標準色"
        case .blue: "ブルー"
        case .amber: "アンバー"
        case .green: "グリーン"
        case .pink: "ピンク"
        }
    }
}
