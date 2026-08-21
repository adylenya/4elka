import Testing
import Foundation
import Carbon.HIToolbox
@testable import ChelkaCore

// MARK: - Значения по умолчанию

@Test func defaultsMatchConfig() {
    let d = Settings.defaults
    #expect(d.batteryLow == Config.Battery.lowThreshold)
    #expect(d.batteryHigh == Config.Battery.highThreshold)
    #expect(d.activityDuration == Config.Activity.duration)
}

@Test func defaultsCoverEveryConfigValueTheyOverride() {
    let d = Settings.defaults
    #expect(d.textLimit == Config.History.textLimit)
    #expect(d.imageLimit == Config.History.imageLimit)
    #expect(d.fileLimit == Config.History.fileLimit)
    #expect(d.maxImageBytes == Config.History.maxImageBytes)
    #expect(d.batteryHysteresis == Config.Battery.hysteresis)
    #expect(d.weatherLatitude == Config.Weather.latitude)
    #expect(d.weatherLongitude == Config.Weather.longitude)
    #expect(d.weatherRefreshInterval == Config.Weather.refreshInterval)
    #expect(d.weatherStaleAfter == Config.Weather.staleAfter)
    #expect(d.blockedBundleIDs.sorted() == IgnoreRules.defaultBlocked.sorted())
}

/// Значения по умолчанию обязаны быть допустимыми: иначе первый же прогон
/// проверки молча подменил бы их чем-то другим.
@Test func defaultsSurviveSanitizing() {
    #expect(Settings.defaults.sanitized() == Settings.defaults)
}

/// Повторная проверка ничего не меняет — иначе сохранение при каждом изменении
/// уводило бы значения всё дальше.
@Test func sanitizingIsIdempotent() {
    var s = Settings.defaults
    s.batteryLow = 90
    s.batteryHigh = 10
    s.activityDuration = -5
    s.textLimit = 0
    let once = s.sanitized()
    #expect(once.sanitized() == once)
}

// MARK: - Проверка ввода

@Test func sanitizeKeepsThresholdsInOrderAndInRange() {
    var s = Settings.defaults
    s.batteryLow = 90
    s.batteryHigh = 10
    let fixed = s.sanitized()
    #expect(fixed.batteryLow < fixed.batteryHigh)
    #expect((1...99).contains(fixed.batteryLow))
    #expect((1...100).contains(fixed.batteryHigh))
}

/// Равные пороги означают, что «мало» и «хватит» — одно и то же значение,
/// и уведомления начали бы драться друг с другом на одном проценте.
@Test func sanitizeSeparatesEqualThresholds() {
    var s = Settings.defaults
    s.batteryLow = 50
    s.batteryHigh = 50
    #expect(s.sanitized().batteryLow < s.sanitized().batteryHigh)

    s.batteryLow = 100
    s.batteryHigh = 100
    let extreme = s.sanitized()
    #expect(extreme.batteryLow < extreme.batteryHigh)
    #expect((1...100).contains(extreme.batteryHigh))
}

@Test func sanitizeRejectsAbsurdCardDuration() {
    var s = Settings.defaults
    s.activityDuration = -5
    #expect(s.sanitized().activityDuration > 0)
    s.activityDuration = 9999
    #expect(s.sanitized().activityDuration <= 30)
}

@Test func sanitizeKeepsCoordinatesOnEarth() {
    var s = Settings.defaults
    s.weatherLatitude = 500
    s.weatherLongitude = -900
    let fixed = s.sanitized()
    #expect((-90.0...90.0).contains(fixed.weatherLatitude))
    #expect((-180.0...180.0).contains(fixed.weatherLongitude))
}

/// Ноль в квоте означал бы историю, из которой всё вылетает в момент записи.
@Test func sanitizeKeepsQuotasAtLeastOne() {
    var s = Settings.defaults
    s.textLimit = 0
    s.imageLimit = -3
    s.fileLimit = 999_999
    let fixed = s.sanitized()
    #expect(fixed.textLimit >= 1)
    #expect(fixed.imageLimit >= 1)
    #expect(fixed.fileLimit <= Config.Limits.historyQuota.upperBound)
}

@Test func sanitizeKeepsImageCeilingPositive() {
    var s = Settings.defaults
    s.maxImageMegabytes = 0
    #expect(s.sanitized().maxImageMegabytes >= 1)
    s.maxImageMegabytes = 100_000
    #expect(s.sanitized().maxImageMegabytes <= Config.Limits.imageMegabytes.upperBound)
}

/// Пустой список — не выбор человека, а потерянная защита: соглашение
/// nspasteboard закрывает только те менеджеры паролей, которые его соблюдают,
/// и опорный список должен существовать всегда.
@Test func sanitizeRestoresBlockListWhenEmptied() {
    var s = Settings.defaults
    s.blockedBundleIDs = []
    #expect(s.sanitized().blockedBundleIDs.sorted() == IgnoreRules.defaultBlocked.sorted())

    s.blockedBundleIDs = ["  ", ""]
    #expect(s.sanitized().blockedBundleIDs.sorted() == IgnoreRules.defaultBlocked.sorted())
}

@Test func sanitizeCleansBundleIDsWithoutLoweringCase() {
    var s = Settings.defaults
    s.blockedBundleIDs = ["  com.apple.Safari  ", "com.apple.Safari", "", "org.mozilla.firefox"]
    let fixed = s.sanitized().blockedBundleIDs
    #expect(fixed == ["com.apple.Safari", "org.mozilla.firefox"])
}

@Test func sanitizeKeepsHysteresisSane() {
    var s = Settings.defaults
    s.batteryHysteresis = 0
    #expect(s.sanitized().batteryHysteresis >= Config.Limits.hysteresis.lowerBound)
    s.batteryHysteresis = 500
    #expect(s.sanitized().batteryHysteresis <= Config.Limits.hysteresis.upperBound)
}

/// Порог устаревания ниже интервала обновления означал бы, что погода всегда
/// показана с пометкой «устарела», даже сразу после успешного обновления.
@Test func sanitizeKeepsStaleThresholdAboveRefresh() {
    var s = Settings.defaults
    s.weatherRefreshMinutes = 30
    s.weatherStaleMinutes = 5
    let fixed = s.sanitized()
    #expect(fixed.weatherStaleMinutes >= fixed.weatherRefreshMinutes)

    s.weatherRefreshMinutes = 0
    #expect(s.sanitized().weatherRefreshMinutes >= Config.Limits.weatherRefreshMinutes.lowerBound)
}

@Test func sanitizeKeepsFirstWeekdayInWeek() {
    var s = Settings.defaults
    s.firstWeekday = 0
    #expect((1...7).contains(s.sanitized().firstWeekday))
    s.firstWeekday = 99
    #expect((1...7).contains(s.sanitized().firstWeekday))
}

/// Комбинация без ⌘/⌃/⌥ глобальным хоткеем быть не может: она отобрала бы
/// у человека обычную букву во всех приложениях.
@Test func sanitizeRejectsHotkeyWithoutRealModifier() {
    var s = Settings.defaults
    s.hotkeyModifiers = 0
    #expect(s.sanitized().hotkeyModifiers == Config.Hotkey.modifiers)
    #expect(s.sanitized().hotkeyKeyCode == Config.Hotkey.keyCode)

    s = Settings.defaults
    s.hotkeyKeyCode = 9999
    #expect(s.sanitized().hotkeyKeyCode == Config.Hotkey.keyCode)
}

@Test func defaultHotkeyDoesNotStealPasteWithoutFormatting() {
    // Проверяем требование, а не конкретные клавиши: сочетание по умолчанию
    // обязано быть не ⌘⇧V. Это системная «вставка без форматирования» почти во
    // всех редакторах и браузерах, а глобальная регистрация забирает сочетание
    // себе — приложение ломало бы то, чем человек пользуется ежедневно.
    #expect(Settings.defaults.hotkeyDisplayName != "⌘⇧V")
    #expect(Settings.defaults.hotkeyModifiers != Int(cmdKey | shiftKey))
    // Сочетание по умолчанию обязано быть среди предлагаемых в настройках,
    // иначе окно покажет пустой выбор при незанятых настройках.
    #expect(HotkeyChoice.all.contains(HotkeyChoice.defaultChoice))
    #expect(HotkeyChoice.all.allSatisfy { !$0.displayName.isEmpty })
    // И ни одно из предлагаемых сочетаний не должно быть ⌘⇧V.
    #expect(HotkeyChoice.all.allSatisfy { $0.displayName != "⌘⇧V" })
}

// MARK: - Производные значения

@Test func derivedValuesFollowTheirFields() {
    var s = Settings.defaults
    s.maxImageMegabytes = 5
    #expect(s.maxImageBytes == 5 * 1024 * 1024)

    s.weatherRefreshMinutes = 20
    s.weatherStaleMinutes = 90
    #expect(s.weatherRefreshInterval == 20 * 60)
    #expect(s.weatherStaleAfter == 90 * 60)

    s.textLimit = 7
    s.imageLimit = 8
    s.fileLimit = 9
    #expect(s.historyQuotas == HistoryQuotas(text: 7, image: 8, files: 9))
}

@Test func cardSourceTogglesGateTheirKind() {
    var s = Settings.defaults
    #expect(s.allowsCard(.track))
    #expect(s.allowsCard(.clipboard))
    #expect(s.allowsCard(.battery))

    s.cardsFromTrack = false
    s.cardsFromBattery = false
    #expect(!s.allowsCard(.track))
    #expect(s.allowsCard(.clipboard))
    #expect(!s.allowsCard(.battery))
}

/// «По системе» означает отсутствие своего значения, а не хранимую копию
/// системного: иначе смена региона в системе перестала бы доходить до календаря.
@Test func calendarFirstWeekdayIsAbsentWhenFollowingSystem() {
    var s = Settings.defaults
    #expect(s.firstWeekdayFollowsSystem)
    #expect(s.calendarFirstWeekday == nil)

    s.firstWeekdayFollowsSystem = false
    s.firstWeekday = 2
    #expect(s.calendarFirstWeekday == 2)
}

// MARK: - Хранение на диске

@Test func roundTripsThroughDisk() {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("settings-\(UUID().uuidString).json")
    var s = Settings.defaults
    s.cardsFromTrack = false
    SettingsStore(fileURL: url).save(s)
    #expect(SettingsStore(fileURL: url).load().cardsFromTrack == false)
}

@Test func roundTripsEveryField() {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("settings-all-\(UUID().uuidString).json")
    var s = Settings.defaults
    s.textLimit = 11
    s.imageLimit = 12
    s.fileLimit = 13
    s.maxImageMegabytes = 14
    s.blockedBundleIDs = ["com.example.one", "com.example.two"]
    s.activityDuration = 4
    s.cardsFromClipboard = false
    s.cardsFromBattery = false
    s.batteryLow = 15
    s.batteryHigh = 75
    s.batteryHysteresis = 3
    s.showsPhone = false
    s.weatherLatitude = 43.2
    s.weatherLongitude = 76.9
    s.weatherCity = "Алматы"
    s.weatherRefreshMinutes = 20
    s.weatherStaleMinutes = 120
    s.firstWeekdayFollowsSystem = false
    s.firstWeekday = 1
    s.showsArtwork = false
    s.showsPositionBar = false
    s.opensOnHover = false
    let store = SettingsStore(fileURL: url)
    store.save(s)
    #expect(store.load() == s.sanitized())
}

@Test func missingOrCorruptFileYieldsDefaults() {
    let dir = FileManager.default.temporaryDirectory
    let missing = dir.appendingPathComponent("нет-\(UUID().uuidString).json")
    #expect(SettingsStore(fileURL: missing).load() == Settings.defaults)

    let corrupt = dir.appendingPathComponent("битый-\(UUID().uuidString).json")
    try? Data("не json".utf8).write(to: corrupt)
    #expect(SettingsStore(fileURL: corrupt).load() == Settings.defaults)
}

/// Обрезанный на середине файл — то, что остаётся после отключения питания.
/// Читаться он обязан как значения по умолчанию, а не ронять приложение.
@Test func truncatedFileYieldsDefaults() {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("обрезанный-\(UUID().uuidString).json")
    let full = try? JSONEncoder().encode(Settings.defaults)
    let half = full.map { $0.prefix($0.count / 2) } ?? Data()
    try? Data(half).write(to: url)
    #expect(SettingsStore(fileURL: url).load() == Settings.defaults)
}

/// Файл с частью полей — это старая версия настроек. Знакомые поля обязаны
/// сохраниться, незнакомые взяться из значений по умолчанию, а не обнулить всё.
@Test func partialFileKeepsKnownFieldsAndDefaultsTheRest() {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("частичный-\(UUID().uuidString).json")
    try? Data(#"{"batteryLow": 15, "cardsFromTrack": false}"#.utf8).write(to: url)
    let loaded = SettingsStore(fileURL: url).load()
    #expect(loaded.batteryLow == 15)
    #expect(loaded.cardsFromTrack == false)
    #expect(loaded.batteryHigh == Settings.defaults.batteryHigh)
    #expect(loaded.blockedBundleIDs == Settings.defaults.blockedBundleIDs)
}

/// Прочитанное с диска тоже проходит проверку: файл мог быть поправлен руками.
@Test func loadSanitizesWhatItReads() {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("правленный-\(UUID().uuidString).json")
    try? Data(#"{"batteryLow": 90, "batteryHigh": 10, "activityDuration": -5}"#.utf8)
        .write(to: url)
    let loaded = SettingsStore(fileURL: url).load()
    #expect(loaded.batteryLow < loaded.batteryHigh)
    #expect(loaded.activityDuration > 0)
}

/// Запись атомарная: после сохранения рядом не должно оставаться временных
/// огрызков, а прежний файл не должен превратиться в половину.
@Test func saveLeavesNoTemporaryLeftovers() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("settings-atomic-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("settings.json")
    let store = SettingsStore(fileURL: url)
    var s = Settings.defaults
    store.save(s)
    s.batteryLow = 12
    store.save(s)
    let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    #expect(files == ["settings.json"])
    #expect(store.load().batteryLow == 12)
}

/// Сохранение в каталог, которого ещё нет, обязано его создать — при первом
/// запуске каталога приложения не существует.
@Test func saveCreatesMissingDirectory() {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("нет-каталога-\(UUID().uuidString)")
        .appendingPathComponent("вложенный")
        .appendingPathComponent("settings.json")
    var s = Settings.defaults
    s.opensOnHover = false
    SettingsStore(fileURL: url).save(s)
    #expect(SettingsStore(fileURL: url).load().opensOnHover == false)
}
