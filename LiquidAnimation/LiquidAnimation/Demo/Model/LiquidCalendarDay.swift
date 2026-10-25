import Foundation

/// 日付を識別子とするサンプル。量は目標に対する割合で、日付を再表示しても変わらない。
nonisolated struct LiquidCalendarDay: Identifiable, Sendable {
    let date: Date
    let number: Int
    let fraction: Double
    let isInMonth: Bool

    var id: Date { date }
}
