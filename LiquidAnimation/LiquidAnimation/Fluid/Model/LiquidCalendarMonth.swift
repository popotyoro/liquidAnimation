import Foundation

/// 月の日数・週の開始曜日・前後月の余白をCalendarで求める。秒数による日付加算はしない。
nonisolated struct LiquidCalendarMonth: Sendable {
    let start: Date
    let days: [LiquidCalendarDay]
    let calendar: Calendar

    init(containing date: Date, calendar: Calendar = .current) {
        self.calendar = calendar
        let start = calendar.dateInterval(of: .month, for: date)!.start
        self.start = start
        let dayCount = calendar.range(of: .day, in: .month, for: start)!.count
        let leading = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        let cellCount = ((leading + dayCount + 6) / 7) * 7
        let monthNumber = calendar.component(.month, from: start)
        days = (0..<cellCount).map { index in
            let offset = index - leading
            let date = calendar.date(byAdding: .day, value: offset, to: start)!
            let isInMonth = (0..<dayCount).contains(offset)
            // 日によって異なる0〜100%のデモ量。実際の飲用記録ではない。
            let fraction = isInMonth ? Double(((offset + 1) * 7 + monthNumber) % 11) / 10 : 0
            return LiquidCalendarDay(date: date, number: calendar.component(.day, from: date),
                                     fraction: fraction, isInMonth: isInMonth)
        }
    }

    func shifted(by months: Int) -> Self {
        Self(containing: calendar.date(byAdding: .month, value: months, to: start)!, calendar: calendar)
    }
}
