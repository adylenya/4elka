import SwiftUI

/// Сетка месяца: название и год со стрелками переключения, строка дней недели,
/// числа. Выходные — приглушённым текстом, сегодня — заливка кружком, `nil` —
/// пустая клетка. Тема только системная: здесь используются исключительно
/// семантические цвета (`.primary`, `.secondary`, `Color.accentColor`),
/// светлая/тёмная тема достаётся бесплатно от системы.
///
/// Вьюха тонкая и не покрывается тестами — вся математика живёт в `MonthGrid`.
public struct MonthView: View {
    private let calendar: Calendar
    private let locale: Locale

    @State private var grid: MonthGrid

    public init(calendar: Calendar = .current, locale: Locale = .current) {
        self.calendar = calendar
        self.locale = locale
        _grid = State(initialValue: MonthView.currentGrid(calendar: calendar, locale: locale))
    }

    public var body: some View {
        VStack(spacing: 8) {
            header
            weekdayRow
            weeksColumn
        }
        // При каждом раскрытии панели вьюха появляется заново — сбрасываем на
        // текущий месяц, даже если до этого стрелками ушли в другой.
        .onAppear { grid = MonthView.currentGrid(calendar: calendar, locale: locale) }
    }

    private var header: some View {
        HStack {
            Button(action: { shift(by: -1) }) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            Text("\(grid.monthName) \(String(grid.year))")
                .font(.headline)
                .foregroundStyle(.primary)

            Spacer()

            Button(action: { shift(by: 1) }) {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(grid.weekdayTitles.enumerated()), id: \.offset) { _, title in
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var weeksColumn: some View {
        VStack(spacing: 4) {
            ForEach(Array(grid.weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        dayCell(day)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: MonthGrid.Day?) -> some View {
        // Круг — фиксированного размера, а не фон всей (переменной ширины)
        // клетки: иначе он растянется в эллипс вместо круга.
        ZStack {
            if let day, day.isToday {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 24, height: 24)
            }
            if let day {
                Text("\(day.number)")
                    .font(.body)
                    .foregroundStyle(day.isWeekend ? .secondary : .primary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 28)
    }

    private func shift(by months: Int) {
        grid = grid.shifted(by: months, today: Date(), calendar: calendar, locale: locale)
    }

    private static func currentGrid(calendar: Calendar, locale: Locale) -> MonthGrid {
        let today = Date()
        let components = calendar.dateComponents([.year, .month], from: today)
        return MonthGrid.make(year: components.year ?? 1970, month: components.month ?? 1,
                              today: today, calendar: calendar, locale: locale)
    }
}
