import Foundation

/// Страховка от того, что уже случилось: настройка сочетания клавиш крутилась
/// в окне, честно писалась в файл — и не делала ничего, потому что
/// подключить её забыли. Тест на сохранение это не поймал. Этот тип не
/// проверяет поведение сам — он проверяет, что для каждого поля модели есть
/// **заявленный** ответственный: применяющая сторона или сознательное
/// «только для показа».
///
/// Список ведётся руками, а не выводится из кода: автоматический вывод
/// доказал бы только «где-то есть строка с этим именем», а не «оно правда
/// на что-то влияет» — то есть защищал бы от опечатки, а не от этого дефекта.
public enum SettingsApplication {
    /// Поля, у которых есть применяющая сторона где-то в приложении.
    public static let appliedFields: Set<String> = [
        "textLimit", "imageLimit", "fileLimit", "maxImageMegabytes",
        "blockedBundleIDs", "activityDuration",
        "cardsFromTrack", "cardsFromClipboard", "cardsFromBattery",
        "batteryLow", "batteryHigh", "batteryHysteresis", "showsPhone",
        "weatherLatitude", "weatherLongitude", "weatherRefreshMinutes", "weatherStaleMinutes",
        "firstWeekdayFollowsSystem", "firstWeekday",
        "showsArtwork", "showsPositionBar",
        "hotkeyKeyCode", "hotkeyModifiers",
        "opensOnHover", "weatherCity",
    ]

    /// Поля без поведения — они только подпись для человека, а не переключатель.
    public static let cosmeticFields: Set<String> = []

    /// Поля модели, не отмеченные ни применёнными, ни косметическими —
    /// то есть добавленные и забытые. Пусто в норме; непусто значит, что
    /// кто-то добавил поле в `Settings`, не подключив и не пометив его.
    public static var unappliedFields: [String] {
        let known = appliedFields.union(cosmeticFields)
        return Mirror(reflecting: Settings.defaults).children.compactMap { child in
            guard let label = child.label, !known.contains(label) else { return nil }
            return label
        }
    }
}
