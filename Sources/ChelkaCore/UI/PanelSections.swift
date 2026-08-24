import Foundation

/// Разделы раскрытой панели — сверху вниз в теле под челкой. Нижняя полоса
/// (`calendar`, `weather`, `devices`) лежит в одну строку, но разделами они
/// остаются отдельными: наполняются они из разных источников и пустеют
/// независимо друг от друга.
public enum PanelSection: Equatable, Sendable, CaseIterable {
    case player
    case history
    case shelf
    case calendar
    case weather
    case devices
}

/// В каком положении плеер с точки зрения панели.
///
/// «Недоступен» и «ничего не играет» — разные вещи, и панель обязана их
/// различать: первое значит «адаптера нет или он сдался», второе — «плеер жив,
/// музыки нет». Одна строка на оба случая скрывала бы полностью мёртвую
/// подсистему за безобидной надписью.
public enum PlayerPresence: Equatable, Sendable {
    case unavailable
    case idle
    case playing

    /// Недоступный источник перебивает всё: состояние, оставшееся от прошлого
    /// трека, выдавать за живой плеер нельзя — кнопки в этом положении никуда
    /// не ведут.
    public static func make(isAvailable: Bool, isEmpty: Bool) -> PlayerPresence {
        guard isAvailable else { return .unavailable }
        return isEmpty ? .idle : .playing
    }
}

/// Строки-заглушки. Живут в одном месте, потому что их показывает вьюха
/// раздела, а решает про них чистая функция ниже: два независимых набора слов
/// разошлись бы в первый же день.
public enum PanelPlaceholder {
    public static let playerUnavailable = "плеер недоступен"
    public static let playerIdle = "ничего не играет"
    public static let weather = "погода недоступна"
    public static let devices = "зарядов не видно"
}

/// Раздел и то, чем он наполнен: либо содержимым, либо строкой-заглушкой.
public struct PanelSectionPlan: Equatable, Sendable {
    public let section: PanelSection
    /// Строка-заглушка, если наполнять раздел нечем. `nil` — есть содержимое.
    public let placeholder: String?

    public init(section: PanelSection, placeholder: String?) {
        self.section = section
        self.placeholder = placeholder
    }
}

/// Состав раскрытой панели — чистая функция от состояния, без окон и без вью.
///
/// Главное правило: **раздел не пропадает, когда наполнять его нечем**. Погода
/// обновляется раз в четверть часа, заряды раз в минуту, плеер — при каждой
/// смене трека; исчезающий раздел дёргал бы раскладку при каждом таком
/// обновлении, и человек ловил бы мышью уезжающие из-под курсора кнопки.
public enum PanelSections {
    /// Порядок сверху вниз. Перестановка — это другая панель, а не деталь
    /// отрисовки, поэтому порядок объявлен явно, а не выведен из `allCases`.
    public static let order: [PanelSection] = [
        .player, .history, .shelf, .calendar, .weather, .devices,
    ]

    /// Какие разделы видны. Ответ один и тот же при любых данных — в этом и
    /// смысл: данные решают, что внутри раздела, а не быть ли ему вовсе.
    public static func visible(hasPlayer: Bool, hasWeather: Bool,
                               hasDevices: Bool) -> [PanelSection] {
        plan(player: hasPlayer ? .playing : .unavailable,
             hasWeather: hasWeather, hasDevices: hasDevices).map(\.section)
    }

    /// План отрисовки: у каждого раздела либо содержимое, либо заглушка.
    public static func plan(player: PlayerPresence, hasWeather: Bool,
                            hasDevices: Bool) -> [PanelSectionPlan] {
        order.map { section in
            PanelSectionPlan(section: section,
                             placeholder: placeholder(for: section, player: player,
                                                      hasWeather: hasWeather,
                                                      hasDevices: hasDevices))
        }
    }

    /// История и полка своих заглушек здесь не получают: они объясняют пустоту
    /// сами и разными словами («история пуста» против «ничего не нашлось»,
    /// «перетащите файлы сюда»), а общая строка стёрла бы эту разницу.
    /// Календарь наполнен всегда — месяц есть любой.
    private static func placeholder(for section: PanelSection, player: PlayerPresence,
                                    hasWeather: Bool, hasDevices: Bool) -> String? {
        switch section {
        case .player:
            switch player {
            case .unavailable: return PanelPlaceholder.playerUnavailable
            case .idle: return PanelPlaceholder.playerIdle
            case .playing: return nil
            }
        case .weather:
            return hasWeather ? nil : PanelPlaceholder.weather
        case .devices:
            return hasDevices ? nil : PanelPlaceholder.devices
        case .history, .shelf, .calendar:
            return nil
        }
    }
}
