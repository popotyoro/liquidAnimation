import Foundation
import LiquidFluid

extension FluidKind {
    var name: LocalizedStringResource {
        switch self {
        case .water: "水"
        case .beer: "ビール"
        case .sparklingWater: "炭酸水"
        case .viscousWater: "粘度のある水"
        }
    }
}
