import Testing
import Foundation
@testable import ChelkaCore

/// Состав раскрытой панели — чистая функция от состояния, без окон и без вью.
/// Проверяется именно то, что раздел НЕ пропадает, когда наполнять его нечем:
/// исчезающий раздел дёргает раскладку при каждом обновлении данных, а данные
/// здесь обновляются сами — погода раз в четверть часа, заряды раз в минуту.

// MARK: - Разделы не пропадают

@Test func sectionsAreStableWhenDataIsMissing() {
    let full = PanelSections.visible(hasPlayer: true, hasWeather: true, hasDevices: true)
    let empty = PanelSections.visible(hasPlayer: false, hasWeather: false, hasDevices: false)
    #expect(full == empty)
    // Одного равенства мало: два пустых списка тоже равны, и такой тест
    // остался бы зелёным, если бы панель перестала показывать вообще всё.
    #expect(full == PanelSections.order)
    #expect(full.count == PanelSection.allCases.count)
    #expect(!full.isEmpty)
}

/// Порядок сверху вниз задан требованием: плеер, история, полка, нижняя полоса
/// (календарь, погода, заряды). Перестановка — это другая панель, а не деталь.
@Test func sectionsGoTopToBottomInTheOrderTheyAreAskedFor() {
    #expect(PanelSections.order == [.player, .history, .shelf, .calendar, .weather, .devices])
}

// MARK: - Заглушки вместо пустого места

@Test func everySectionWithoutDataStillSaysSomething() {
    let plan = PanelSections.plan(player: .unavailable, hasWeather: false, hasDevices: false)
    #expect(plan.count == PanelSections.order.count)
    for entry in plan where entry.section == .player || entry.section == .weather
        || entry.section == .devices {
        guard let text = entry.placeholder else {
            Issue.record("раздел \(entry.section) нечем наполнить и он молчит")
            continue
        }
        #expect(!text.isEmpty)
    }
}

@Test func filledSectionsHaveNoPlaceholderAtAll() {
    let plan = PanelSections.plan(player: .playing, hasWeather: true, hasDevices: true)
    #expect(plan.allSatisfy { $0.placeholder == nil })
}

/// История и полка сами объясняют свою пустоту разными словами («история пуста»
/// против «ничего не нашлось», «перетащите файлы сюда»), поэтому общей заглушки
/// у них нет — но и пропадать они не имеют права.
@Test func historyAndShelfWordTheirOwnEmptinessAndNeverVanish() {
    let plan = PanelSections.plan(player: .unavailable, hasWeather: false, hasDevices: false)
    let own = plan.filter { $0.section == .history || $0.section == .shelf }
    #expect(own.count == 2)
    #expect(own.allSatisfy { $0.placeholder == nil })
}

/// Календарь наполнен всегда: месяц есть любой, даже если сегодня нечего
/// показать. Заглушка ему не нужна, а исчезать он не должен.
@Test func calendarIsAlwaysFilled() {
    let plan = PanelSections.plan(player: .unavailable, hasWeather: false, hasDevices: false)
    #expect(plan.first { $0.section == .calendar }?.placeholder == nil)
}

// MARK: - Плеер: три положения, и ни одно из них не молчит

@Test func deadPlayerSaysSoInsteadOfLookingLikeSilence() {
    // Недоступный источник и «ничего не играет» — разные вещи: первое значит
    // «адаптера нет или он сдался», второе — «плеер жив, музыки нет».
    #expect(PlayerPresence.make(isAvailable: false, isEmpty: true) == .unavailable)
    #expect(PlayerPresence.make(isAvailable: true, isEmpty: true) == .idle)
    #expect(PlayerPresence.make(isAvailable: true, isEmpty: false) == .playing)
    #expect(PanelPlaceholder.playerUnavailable != PanelPlaceholder.playerIdle)
}

/// Источник умер — состояние, оставшееся от прошлого трека, выдавать за живой
/// плеер нельзя: кнопки в этом положении никуда не ведут.
@Test func lastKnownTrackIsNotShownAsLiveAfterTheSourceDied() {
    #expect(PlayerPresence.make(isAvailable: false, isEmpty: false) == .unavailable)
}

// MARK: - Заряды: настройка про айфон обязана доходить до списка

@Test func hidingThePhoneRemovesItFromTheListAndKeepsTheRest() {
    let devices = [
        DeviceCharge(name: "MacBook", percent: 54, isCharging: false, source: .mac,
                     symbol: "laptopcomputer"),
        DeviceCharge(name: "AirPods", percent: 100, isCharging: false, source: .bluetooth,
                     symbol: "airpods"),
        DeviceCharge(name: "Айфон", percent: 76, isCharging: true, source: .phone,
                     symbol: "iphone"),
    ]
    let hidden = DeviceList.visible(devices, showsPhone: false)
    #expect(hidden.map(\.name) == ["MacBook", "AirPods"])
    // Порядок остаётся: мак первым, а не «как получилось после фильтра».
    #expect(DeviceList.visible(devices, showsPhone: true).map(\.name) == devices.map(\.name))
}

// MARK: - Календарь: первый день недели из настроек

@Test func firstWeekdayFromSettingsReachesTheMonthCalendar() {
    var manual = Settings.defaults
    manual.firstWeekdayFollowsSystem = false
    manual.firstWeekday = 1
    #expect(manual.monthCalendar.firstWeekday == 1)

    var monday = manual
    monday.firstWeekday = 2
    #expect(monday.monthCalendar.firstWeekday == 2)
}

/// «По системе» — это отсутствие своего значения, а не его копия: иначе смена
/// региона в системных настройках перестала бы доходить до календаря.
@Test func systemFirstWeekdayIsTakenFromTheSystemAndNotFrozen() {
    var system = Settings.defaults
    system.firstWeekdayFollowsSystem = true
    system.firstWeekday = 1
    #expect(system.monthCalendar.firstWeekday == Calendar.current.firstWeekday)
}

// MARK: - Раскрытой панели обязано хватать высоты на все разделы

@Test func expandedPanelFitsEverySectionOfIt() {
    // Замерено 24.08: при 340 точках содержимого влезали только сетка истории
    // и полка — плеер и нижняя полоса обрезались нижним краем. Высота обязана
    // складываться из разделов, а не быть круглым числом.
    let needed = Config.Panel.playerHeight
        + Config.HistoryGrid.minHeight
        + Config.Shelf.stripHeight
        + Config.Panel.bottomBarHeight
        + Config.Panel.sectionSpacing * CGFloat(Config.Panel.verticalSections - 1)
        // Отступы по краям тоже занимают место: не учтённые, они отбирали его
        // у сетки истории, и нижняя строка плиток обрезалась.
        + Config.Panel.verticalPadding * 2
    #expect(Config.Notch.expandedSize.height >= needed)
}

@Test func bottomBarFitsTheTallestMonthGrid() {
    // Месяц из 31 дня, начинающийся в последний день недели, даёт шесть строк.
    // Полоса, посчитанная под пять, обрезала бы последнюю неделю.
    let weeks = CGFloat(Config.Calendar.maxWeeks)
    let grid = weeks * Config.Calendar.dayCellHeight
        + (weeks - 1) * Config.Calendar.rowSpacing
    #expect(Config.Panel.bottomBarHeight
            >= grid + Config.Calendar.headerHeight + Config.Calendar.weekdayRowHeight)
}

@Test func bottomBarLeavesRoomBesideTheCalendarForWeatherAndCharges() {
    // Календарь занимает левую часть полосы; погода и заряды живут справа.
    // Если календарь шире полосы, справа не остаётся ничего.
    #expect(Config.Panel.calendarWidth < Config.Notch.expandedSize.width / 2)
}

@Test func playerRowIsTallEnoughForItsArtwork() {
    #expect(Config.Panel.playerHeight >= Config.Media.artworkSide)
}
