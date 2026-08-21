import Testing
import Foundation
@testable import ChelkaCore

private var mondayFirst: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Almaty")!
    c.firstWeekday = 2
    return c
}

/// Локаль передаётся явно, а не берётся из календаря. Замерено: у созданного
/// руками `Calendar` локаль не nil, а ПУСТАЯ, и `?? .current` её не перекрывает —
/// в результате `DateFormatter` уходит в инвариантную локаль и выдаёт «M08»
/// вместо «AUGUST». Явный параметр заодно делает тесты независимыми от
/// настроек машины, на которой они запущены.
private let systemLocale = Locale(identifier: "en_KZ")

private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
    mondayFirst.date(from: DateComponents(year: y, month: m, day: d))!
}

@Test func august2026StartsOnSaturdayWithMondayFirstWeek() {
    let g = MonthGrid.make(year: 2026, month: 8, today: date(2026, 8, 21), calendar: mondayFirst, locale: systemLocale)
    #expect(g.weeks[0].prefix(5).allSatisfy { $0 == nil })
    #expect(g.weeks[0][5]?.number == 1)
    #expect(g.weeks[0][6]?.number == 2)
}

@Test func allDaysOfAugustArePresentExactlyOnce() {
    let g = MonthGrid.make(year: 2026, month: 8, today: date(2026, 8, 21), calendar: mondayFirst, locale: systemLocale)
    let numbers = g.weeks.flatMap { $0 }.compactMap { $0?.number }
    #expect(numbers == Array(1...31))
}

@Test func todayIsMarkedOnlyOnce() {
    let g = MonthGrid.make(year: 2026, month: 8, today: date(2026, 8, 21), calendar: mondayFirst, locale: systemLocale)
    let marked = g.weeks.flatMap { $0 }.compactMap { $0 }.filter(\.isToday)
    #expect(marked.count == 1)
    #expect(marked.first?.number == 21)
}

@Test func todayIsNotMarkedInOtherMonths() {
    let g = MonthGrid.make(year: 2026, month: 9, today: date(2026, 8, 21), calendar: mondayFirst, locale: systemLocale)
    #expect(!g.weeks.flatMap { $0 }.compactMap { $0 }.contains { $0.isToday })
}

@Test func weekendsAreSaturdayAndSunday() {
    let g = MonthGrid.make(year: 2026, month: 8, today: date(2026, 8, 21), calendar: mondayFirst, locale: systemLocale)
    let first = g.weeks[0]
    #expect(first[5]?.isWeekend == true)   // 1 августа, суббота
    #expect(first[6]?.isWeekend == true)   // 2 августа, воскресенье
    let second = g.weeks[1]
    #expect(second[0]?.isWeekend == false) // 3 августа, понедельник
}

@Test func februaryInLeapYearHas29Days() {
    let g = MonthGrid.make(year: 2028, month: 2, today: date(2026, 8, 21), calendar: mondayFirst, locale: systemLocale)
    #expect(g.weeks.flatMap { $0 }.compactMap { $0?.number }.last == 29)
}

@Test func februaryInCommonYearHas28Days() {
    let g = MonthGrid.make(year: 2026, month: 2, today: date(2026, 8, 21), calendar: mondayFirst, locale: systemLocale)
    #expect(g.weeks.flatMap { $0 }.compactMap { $0?.number }.last == 28)
}

@Test func shiftingWrapsAcrossYearBoundary() {
    let december = MonthGrid.make(year: 2026, month: 12, today: date(2026, 8, 21), calendar: mondayFirst, locale: systemLocale)
    let january = december.shifted(by: 1, today: date(2026, 8, 21), calendar: mondayFirst, locale: systemLocale)
    #expect(january.year == 2027)
    #expect(january.month == 1)

    let previous = MonthGrid.make(year: 2026, month: 1, today: date(2026, 8, 21), calendar: mondayFirst, locale: systemLocale)
        .shifted(by: -1, today: date(2026, 8, 21), calendar: mondayFirst, locale: systemLocale)
    #expect(previous.year == 2025)
    #expect(previous.month == 12)
}

@Test func monthNameIsNotTheInvariantFallback() {
    // Замер показал ловушку: при пустой локали DateFormatter выдаёт «M08».
    let g = MonthGrid.make(year: 2026, month: 8, today: date(2026, 8, 21),
                           calendar: mondayFirst, locale: systemLocale)
    #expect(g.monthName == "AUGUST")
}

@Test func weekdayTitlesComeFromSystemLocale() {
    // На целевой машине системный язык en-KZ, поэтому в календаре ожидаются
    // латинские однобуквенные подписи, начинающиеся с понедельника — как в
    // системном календаре, с которым владелец сравнивает.
    let g = MonthGrid.make(year: 2026, month: 8, today: date(2026, 8, 21), calendar: mondayFirst, locale: systemLocale)
    #expect(g.weekdayTitles.count == 7)
    #expect(g.weekdayTitles.first == "M")
    #expect(g.weekdayTitles.last == "S")
}

@Test func weekdayTitlesFollowFirstWeekdaySetting() {
    var sundayFirst = mondayFirst
    sundayFirst.firstWeekday = 1
    let m = MonthGrid.make(year: 2026, month: 8, today: date(2026, 8, 21), calendar: mondayFirst, locale: systemLocale)
    let s = MonthGrid.make(year: 2026, month: 8, today: date(2026, 8, 21), calendar: sundayFirst, locale: systemLocale)
    #expect(m.weekdayTitles != s.weekdayTitles)
    #expect(m.weekdayTitles.count == 7)
}
