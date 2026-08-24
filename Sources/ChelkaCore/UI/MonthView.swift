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
        VStack(spacing: Config.Calendar.sectionSpacing) {
            header
            weekdayRow
            weeksColumn
        }
        // При каждом раскрытии панели вьюха появляется заново — сбрасываем на
        // текущий месяц, даже если до этого стрелками ушли в другой.
        .onAppear { grid = MonthView.currentGrid(calendar: calendar, locale: locale) }
    }

    private var header: some View {
        HStack(spacing: Config.Calendar.rowSpacing) {
            Button(action: { shift(by: -1) }) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            Text("\(grid.monthName) \(String(grid.year))")
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            Button(action: { shift(by: 1) }) {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        // Высота заголовка задана, а не выведена из шрифта: из неё считается
        // высота нижней полосы панели, и она не должна зависеть от того, во
        // сколько строк лёг «СЕНТЯБРЬ 2026» на этой конкретной машине.
        .frame(height: Config.Calendar.headerHeight)
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
        .frame(height: Config.Calendar.weekdayRowHeight)
    }

    private var weeksColumn: some View {
        VStack(spacing: Config.Calendar.rowSpacing) {
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
                    .frame(width: Config.Calendar.todayCircleSide,
                           height: Config.Calendar.todayCircleSide)
            }
            if let day {
                Text("\(day.number)")
                    .font(.body)
                    .foregroundStyle(day.isWeekend ? .secondary : .primary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: Config.Calendar.dayCellHeight)
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
