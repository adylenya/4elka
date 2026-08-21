import Foundation

public struct MonthGrid: Equatable {
    public struct Day: Equatable {
        public let number: Int
        public let isWeekend: Bool
        public let isToday: Bool
    }

    public let year: Int
    public let month: Int
    public let monthName: String
    public let weekdayTitles: [String]
    public let weeks: [[Day?]]

    public static func make(year: Int, month: Int, today: Date,
                            calendar: Calendar, locale: Locale) -> MonthGrid {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        guard let first = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: first) else {
            return MonthGrid(year: year, month: month, monthName: "",
                             weekdayTitles: titles(calendar, locale), weeks: [])
        }

        // Сколько пустых клеток до первого числа при текущем первом дне недели.
        let weekday = calendar.component(.weekday, from: first)
        let leading = (weekday - calendar.firstWeekday + 7) % 7

        var cells: [Day?] = Array(repeating: nil, count: leading)
        for day in range {
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: first) else { continue }
            cells.append(Day(number: day,
                             isWeekend: calendar.isDateInWeekend(date),
                             isToday: calendar.isDate(date, inSameDayAs: today)))
        }
        while cells.count % 7 != 0 { cells.append(nil) }

        let weeks = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }

        // Локаль ОБЯЗАТЕЛЬНО передаётся снаружи. Замерено: у созданного руками
        // `Calendar` локаль не nil, а пустая, поэтому `calendar.locale` уводит
        // DateFormatter в инвариантную локаль и вместо «AUGUST» выходит «M08».
        // Приложение передаёт `Locale.current`, тесты — фиксированную.
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.dateFormat = "LLLL"

        return MonthGrid(year: year, month: month,
                         monthName: formatter.string(from: first).uppercased(),
                         weekdayTitles: titles(calendar, locale), weeks: weeks)
    }

    public func shifted(by months: Int, today: Date,
                        calendar: Calendar, locale: Locale) -> MonthGrid {
        let total = (year * 12 + (month - 1)) + months
        return MonthGrid.make(year: total / 12, month: total % 12 + 1,
                              today: today, calendar: calendar, locale: locale)
    }

    private static func titles(_ calendar: Calendar, _ locale: Locale) -> [String] {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        guard let symbols = formatter.veryShortStandaloneWeekdaySymbols, symbols.count == 7 else {
            return []
        }
        let start = calendar.firstWeekday - 1
        return (0..<7).map { symbols[(start + $0) % 7] }
    }
}
