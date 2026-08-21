import Foundation

/// Всё, что имеет смысл крутить, одним значением. Тип из одних значений,
/// поэтому `Sendable` достаётся бесплатно и подделок для тестов не нужно.
///
/// Поля объявлены через `var` осознанно: так на них навешиваются биндинги
/// SwiftUI. Иммутабельность это не нарушает — экземпляр меняется копированием
/// (`var next = settings; next.поле = …`), а `sanitized()` возвращает **новый**
/// экземпляр, а не правит себя.
///
/// Значения по умолчанию берутся из `Config` — он остаётся источником истины,
/// а настройки его перекрывают. Дублировать числа здесь нельзя: разойдутся.
public struct Settings: Equatable, Codable, Sendable {
    // Буфер обмена
    public var textLimit: Int
    public var imageLimit: Int
    public var fileLimit: Int
    /// Потолок размера картинки. В мегабайтах, а не в байтах: настройку правит
    /// человек, и «40» он понимает, а «41943040» — нет.
    public var maxImageMegabytes: Int
    /// Приложения, из которых не записывать. Регистр не меняется: настоящие
    /// идентификаторы бывают с большими буквами (`com.apple.Safari`), и
    /// приведение к нижнему регистру сломало бы сравнение.
    public var blockedBundleIDs: [String]

    // Карточки
    public var activityDuration: TimeInterval
    public var cardsFromTrack: Bool
    public var cardsFromClipboard: Bool
    public var cardsFromBattery: Bool

    // Заряд
    public var batteryLow: Int
    public var batteryHigh: Int
    public var batteryHysteresis: Int
    public var showsPhone: Bool

    // Погода
    public var weatherLatitude: Double
    public var weatherLongitude: Double
    /// Подпись к координатам: человек выбирает город, а не вводит числа.
    public var weatherCity: String
    public var weatherRefreshMinutes: Int
    public var weatherStaleMinutes: Int

    // Календарь
    /// «По системе» — это отсутствие своего значения, а не его копия: иначе
    /// смена региона в системных настройках перестала бы доходить до календаря.
    public var firstWeekdayFollowsSystem: Bool
    public var firstWeekday: Int

    // Плеер
    public var showsArtwork: Bool
    public var showsPositionBar: Bool

    // Поведение
    /// Комбинация в карбоновых кодах — тех, что принимает `RegisterEventHotKey`.
    public var hotkeyKeyCode: Int
    public var hotkeyModifiers: Int
    public var opensOnHover: Bool

    public init(textLimit: Int, imageLimit: Int, fileLimit: Int, maxImageMegabytes: Int,
                blockedBundleIDs: [String], activityDuration: TimeInterval,
                cardsFromTrack: Bool, cardsFromClipboard: Bool, cardsFromBattery: Bool,
                batteryLow: Int, batteryHigh: Int, batteryHysteresis: Int, showsPhone: Bool,
                weatherLatitude: Double, weatherLongitude: Double, weatherCity: String,
                weatherRefreshMinutes: Int, weatherStaleMinutes: Int,
                firstWeekdayFollowsSystem: Bool, firstWeekday: Int,
                showsArtwork: Bool, showsPositionBar: Bool,
                hotkeyKeyCode: Int, hotkeyModifiers: Int, opensOnHover: Bool) {
        self.textLimit = textLimit
        self.imageLimit = imageLimit
        self.fileLimit = fileLimit
        self.maxImageMegabytes = maxImageMegabytes
        self.blockedBundleIDs = blockedBundleIDs
        self.activityDuration = activityDuration
        self.cardsFromTrack = cardsFromTrack
        self.cardsFromClipboard = cardsFromClipboard
        self.cardsFromBattery = cardsFromBattery
        self.batteryLow = batteryLow
        self.batteryHigh = batteryHigh
        self.batteryHysteresis = batteryHysteresis
        self.showsPhone = showsPhone
        self.weatherLatitude = weatherLatitude
        self.weatherLongitude = weatherLongitude
        self.weatherCity = weatherCity
        self.weatherRefreshMinutes = weatherRefreshMinutes
        self.weatherStaleMinutes = weatherStaleMinutes
        self.firstWeekdayFollowsSystem = firstWeekdayFollowsSystem
        self.firstWeekday = firstWeekday
        self.showsArtwork = showsArtwork
        self.showsPositionBar = showsPositionBar
        self.hotkeyKeyCode = hotkeyKeyCode
        self.hotkeyModifiers = hotkeyModifiers
        self.opensOnHover = opensOnHover
    }

    public static let defaults = Settings(
        textLimit: Config.History.textLimit,
        imageLimit: Config.History.imageLimit,
        fileLimit: Config.History.fileLimit,
        maxImageMegabytes: Config.History.maxImageBytes / Config.bytesInMegabyte,
        blockedBundleIDs: IgnoreRules.defaultBlocked.sorted(),
        activityDuration: Config.Activity.duration,
        cardsFromTrack: true,
        cardsFromClipboard: true,
        cardsFromBattery: true,
        batteryLow: Config.Battery.lowThreshold,
        batteryHigh: Config.Battery.highThreshold,
        batteryHysteresis: Config.Battery.hysteresis,
        showsPhone: true,
        weatherLatitude: Config.Weather.latitude,
        weatherLongitude: Config.Weather.longitude,
        weatherCity: Config.Weather.cityName,
        weatherRefreshMinutes: Int(Config.Weather.refreshInterval / Config.secondsInMinute),
        weatherStaleMinutes: Int(Config.Weather.staleAfter / Config.secondsInMinute),
        firstWeekdayFollowsSystem: true,
        firstWeekday: Config.Calendar.manualFirstWeekday,
        showsArtwork: Config.Player.showsArtwork,
        showsPositionBar: Config.Player.showsPositionBar,
        hotkeyKeyCode: Config.Hotkey.keyCode,
        hotkeyModifiers: Config.Hotkey.modifiers,
        opensOnHover: Config.Behavior.opensOnHover)
}

// MARK: - Производные значения

public extension Settings {
    /// Потолок размера в байтах — в этом виде его ждут правила игнора.
    var maxImageBytes: Int { maxImageMegabytes * Config.bytesInMegabyte }

    var historyQuotas: HistoryQuotas {
        HistoryQuotas(text: textLimit, image: imageLimit, files: fileLimit)
    }

    /// Правила игнора целиком: список приложений и потолок размера — из
    /// настроек, собственный идентификатор — из `Config`. Своё приложение
    /// отбрасывается при любых настройках: иначе клик по элементу истории
    /// возвращал бы этот элемент в историю по кругу.
    var ignoreRules: IgnoreRules {
        IgnoreRules(blockedBundleIDs: Set(blockedBundleIDs),
                    ownBundleID: Config.ownBundleID,
                    maxBytes: maxImageBytes)
    }

    var weatherRefreshInterval: TimeInterval {
        TimeInterval(weatherRefreshMinutes) * Config.secondsInMinute
    }

    var weatherStaleAfter: TimeInterval {
        TimeInterval(weatherStaleMinutes) * Config.secondsInMinute
    }

    /// Первый день недели или `nil`, если он берётся из системы.
    var calendarFirstWeekday: Int? { firstWeekdayFollowsSystem ? nil : firstWeekday }

    func allowsCard(_ kind: ActivityEvent.Kind) -> Bool {
        switch kind {
        case .track: return cardsFromTrack
        case .clipboard: return cardsFromClipboard
        case .battery: return cardsFromBattery
        }
    }

    var hotkeyChoice: HotkeyChoice {
        HotkeyChoice(keyCode: hotkeyKeyCode, modifiers: hotkeyModifiers)
    }

    var hotkeyDisplayName: String { hotkeyChoice.displayName }

    /// Новый экземпляр с этой комбинацией. Копированием, а не правкой себя.
    func choosing(_ hotkey: HotkeyChoice) -> Settings {
        var next = self
        next.hotkeyKeyCode = hotkey.keyCode
        next.hotkeyModifiers = hotkey.modifiers
        return next
    }

    /// Широта, введённая руками, стирает название города: «Астана» с чужими
    /// координатами — вранье, а пустое название интерфейс показывает как
    /// «координаты вручную».
    func settingLatitude(_ value: Double) -> Settings {
        var next = self
        next.weatherLatitude = value
        if value != weatherLatitude { next.weatherCity = "" }
        return next
    }

    func settingLongitude(_ value: Double) -> Settings {
        var next = self
        next.weatherLongitude = value
        if value != weatherLongitude { next.weatherCity = "" }
        return next
    }

    /// Выбор города — это подстановка координат вместе с названием. Отдельно
    /// они могли бы разойтись: «Астана» с координатами Алматы.
    func choosing(_ city: City) -> Settings {
        var next = self
        next.weatherCity = city.name
        next.weatherLatitude = city.latitude
        next.weatherLongitude = city.longitude
        return next
    }
}

// MARK: - Чтение из файла

public extension Settings {
    /// Каждое поле читается со своим значением по умолчанию. Файл с частью
    /// полей — это настройки прошлой версии, и знакомое из него обязано
    /// сохраниться, а не обнулиться целиком из-за одного отсутствующего ключа.
    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings.defaults
        func read<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? box.decode(T.self, forKey: key)) ?? fallback
        }
        self.init(
            textLimit: read(.textLimit, d.textLimit),
            imageLimit: read(.imageLimit, d.imageLimit),
            fileLimit: read(.fileLimit, d.fileLimit),
            maxImageMegabytes: read(.maxImageMegabytes, d.maxImageMegabytes),
            blockedBundleIDs: read(.blockedBundleIDs, d.blockedBundleIDs),
            activityDuration: read(.activityDuration, d.activityDuration),
            cardsFromTrack: read(.cardsFromTrack, d.cardsFromTrack),
            cardsFromClipboard: read(.cardsFromClipboard, d.cardsFromClipboard),
            cardsFromBattery: read(.cardsFromBattery, d.cardsFromBattery),
            batteryLow: read(.batteryLow, d.batteryLow),
            batteryHigh: read(.batteryHigh, d.batteryHigh),
            batteryHysteresis: read(.batteryHysteresis, d.batteryHysteresis),
            showsPhone: read(.showsPhone, d.showsPhone),
            weatherLatitude: read(.weatherLatitude, d.weatherLatitude),
            weatherLongitude: read(.weatherLongitude, d.weatherLongitude),
            weatherCity: read(.weatherCity, d.weatherCity),
            weatherRefreshMinutes: read(.weatherRefreshMinutes, d.weatherRefreshMinutes),
            weatherStaleMinutes: read(.weatherStaleMinutes, d.weatherStaleMinutes),
            firstWeekdayFollowsSystem: read(.firstWeekdayFollowsSystem, d.firstWeekdayFollowsSystem),
            firstWeekday: read(.firstWeekday, d.firstWeekday),
            showsArtwork: read(.showsArtwork, d.showsArtwork),
            showsPositionBar: read(.showsPositionBar, d.showsPositionBar),
            hotkeyKeyCode: read(.hotkeyKeyCode, d.hotkeyKeyCode),
            hotkeyModifiers: read(.hotkeyModifiers, d.hotkeyModifiers),
            opensOnHover: read(.opensOnHover, d.opensOnHover))
    }
}
