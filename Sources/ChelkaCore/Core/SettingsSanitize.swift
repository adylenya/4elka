import Foundation

/// Приведение настроек в допустимые пределы. Вынесено отдельным файлом:
/// правил много, и они читаются как список требований, а не как приложение
/// к модели.
///
/// Правило одно на всех: `sanitized()` возвращает **новый** экземпляр и
/// никогда не правит себя. Повторный прогон ничего не меняет — иначе
/// сохранение при каждом изменении уводило бы значения всё дальше.
public extension Settings {
    func sanitized() -> Settings {
        var next = self
        next.textLimit = Config.Limits.historyQuota.clamping(textLimit)
        next.imageLimit = Config.Limits.historyQuota.clamping(imageLimit)
        next.fileLimit = Config.Limits.historyQuota.clamping(fileLimit)
        next.maxImageMegabytes = Config.Limits.imageMegabytes.clamping(maxImageMegabytes)
        next.blockedBundleIDs = Self.cleanedBundleIDs(blockedBundleIDs)
        next.activityDuration = Config.Limits.activityDuration.clamping(activityDuration)

        let thresholds = Self.orderedThresholds(low: batteryLow, high: batteryHigh)
        next.batteryLow = thresholds.low
        next.batteryHigh = thresholds.high
        next.batteryHysteresis = Config.Limits.hysteresis.clamping(batteryHysteresis)

        next.weatherLatitude = Config.Limits.latitude.clamping(weatherLatitude)
        next.weatherLongitude = Config.Limits.longitude.clamping(weatherLongitude)
        next.weatherCity = weatherCity.trimmingCharacters(in: .whitespacesAndNewlines)
        let refresh = Config.Limits.weatherRefreshMinutes.clamping(weatherRefreshMinutes)
        next.weatherRefreshMinutes = refresh
        // Порог устаревания ниже интервала обновления означал бы, что погода
        // помечена устаревшей всегда — даже сразу после успешного обновления.
        next.weatherStaleMinutes = max(refresh,
                                       Config.Limits.weatherStaleMinutes.clamping(weatherStaleMinutes))

        next.firstWeekday = Config.Limits.firstWeekday.clamping(firstWeekday)

        let hotkey = Self.validHotkey(keyCode: hotkeyKeyCode, modifiers: hotkeyModifiers)
        next.hotkeyKeyCode = hotkey.keyCode
        next.hotkeyModifiers = hotkey.modifiers
        return next
    }

    /// Пороги обязаны идти по возрастанию и не совпадать: на равных «мало» и
    /// «хватит» срабатывали бы на одном и том же проценте.
    private static func orderedThresholds(low: Int, high: Int) -> (low: Int, high: Int) {
        var lowFixed = Config.Limits.batteryLow.clamping(low)
        var highFixed = Config.Limits.batteryHigh.clamping(high)
        if lowFixed > highFixed { swap(&lowFixed, &highFixed) }
        if lowFixed == highFixed {
            if highFixed < Config.Limits.batteryHigh.upperBound {
                highFixed += 1
            } else {
                lowFixed -= 1
            }
        }
        return (Config.Limits.batteryLow.clamping(lowFixed),
                Config.Limits.batteryHigh.clamping(highFixed))
    }

    /// Пробелы вокруг идентификатора — след копирования из статьи, пустые
    /// строки — след пустой строки в таблице. Регистр не трогаем: настоящие
    /// идентификаторы бывают с большими буквами.
    ///
    /// Пустой список — не выбор человека, а потерянная защита: соглашение
    /// nspasteboard соблюдают не все менеджеры паролей, и опорный список
    /// обязан существовать всегда.
    private static func cleanedBundleIDs(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        let cleaned = raw
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
        return cleaned.isEmpty ? IgnoreRules.defaultBlocked.sorted() : cleaned
    }

    /// Комбинация без ⌘/⌃/⌥ глобальным хоткеем быть не может: она отобрала бы
    /// у человека обычную букву во всех приложениях сразу.
    ///
    /// Незнакомые биты маски отбрасываются до всех проверок: маска уходит в
    /// Carbon беззнаковым числом, а отрицательное значение из правленного
    /// руками файла проверку «есть настоящий модификатор» проходило и
    /// превращалось в мусор при переводе.
    private static func validHotkey(keyCode: Int, modifiers: Int) -> HotkeyChoice {
        let known = modifiers & Config.Hotkey.knownModifiers
        let hasRealModifier = known & Config.Hotkey.requiredModifiers != 0
        guard hasRealModifier, Config.Hotkey.keyCodeRange.contains(keyCode) else {
            return .defaultChoice
        }
        let choice = HotkeyChoice(keyCode: keyCode, modifiers: known)
        // Занятое системой отменяется, даже если человек его когда-то выбрал:
        // прошлая версия предлагала ⌥Пробел и ⌃Пробел, и убрать их из списка
        // выбора мало — из файла настроек они сами не уйдут.
        guard HotkeyChoice.takenBySystem(choice) == nil else { return .defaultChoice }
        return choice
    }
}

extension ClosedRange {
    /// Значение, загнанное в границы. Отдельным расширением, чтобы правила
    /// проверки читались строкой на поле, а не тремя вложенными `min`/`max`.
    func clamping(_ value: Bound) -> Bound {
        Swift.min(Swift.max(value, lowerBound), upperBound)
    }
}
