import Foundation

/// Metalの初期化・描画に失敗した理由を操作画面へ伝える。
nonisolated enum FluidError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? {
        switch self { case .unavailable(let message): message }
    }
}
