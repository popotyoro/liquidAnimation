/// デモの行識別子と目標量。再表示のたびに新しいIDを生成しない。
nonisolated struct LiquidFillSample: Identifiable, Sendable {
    let id: Int
    let target: Double

    static let examples: [Self] = [0.1, 0.25, 0.5, 0.75, 1, 0.35, 0.6, 0.85, 0.15, 0]
        .enumerated().map { Self(id: $0.offset, target: $0.element) }
}
