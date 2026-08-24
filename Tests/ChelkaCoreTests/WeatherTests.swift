import Testing
import Foundation
@testable import ChelkaCore

private let now = Date(timeIntervalSince1970: 10_000)

@Test func decodesRealOpenMeteoResponse() throws {
    let url = try #require(Bundle.module.url(forResource: "Fixtures/open-meteo", withExtension: "json"))
    let snapshot = try #require(WeatherSnapshot.decode(try Data(contentsOf: url), now: now))
    #expect(snapshot.celsius == 21.2)
    #expect(snapshot.feelsLike == 18.4)
    #expect(snapshot.code == 2)
}

@Test func rejectsGarbage() {
    #expect(WeatherSnapshot.decode(Data("не json".utf8), now: now) == nil)
    #expect(WeatherSnapshot.decode(Data(), now: now) == nil)
}

@Test func rejectsResponseWithoutCurrentBlock() {
    #expect(WeatherSnapshot.decode(Data(#"{"latitude":51.1}"#.utf8), now: now) == nil)
}

@Test func rejectsImplausibleTemperature() {
    // Внешним данным не доверяем: 900 градусов — это сбой, а не погода.
    let json = #"{"current":{"temperature_2m":900,"apparent_temperature":10,"weather_code":1,"wind_speed_10m":5}}"#
    #expect(WeatherSnapshot.decode(Data(json.utf8), now: now) == nil)
}

@Test func acceptsExtremeButPlausibleTemperature() {
    let json = #"{"current":{"temperature_2m":-45,"apparent_temperature":-55,"weather_code":0,"wind_speed_10m":20}}"#
    #expect(WeatherSnapshot.decode(Data(json.utf8), now: now)?.celsius == -45)
}

@Test func summaryRoundsToWholeDegrees() {
    let json = #"{"current":{"temperature_2m":21.2,"apparent_temperature":18.4,"weather_code":2,"wind_speed_10m":13.6}}"#
    let snapshot = try! #require(WeatherSnapshot.decode(Data(json.utf8), now: now))
    #expect(snapshot.summary == "21°")
}

@Test func requestURLCarriesAstanaCoordinatesByDefault() {
    let url = WeatherProvider.requestURL(for: .defaults).absoluteString
    #expect(url.contains("latitude=51.1605"))
    #expect(url.contains("longitude=71.4704"))
    #expect(url.contains("Asia/Almaty"))
}

/// Город, выбранный в настройках, обязан доходить до запроса. Раньше запрос
/// собирался из `Config` и был статическим: человек выбирал Алматы, значение
/// честно ложилось в `settings.json` и не меняло ничего.
@Test func cityChosenInSettingsReachesTheRequest() {
    let almaty = City(name: "Алматы", latitude: 43.2389, longitude: 76.8897)
    let settings = Settings.defaults.choosing(almaty)
    let url = WeatherProvider.requestURL(for: settings.weather).absoluteString
    #expect(url.contains("latitude=43.2389"))
    #expect(url.contains("longitude=76.8897"))
}

/// Интервал обновления живёт в уже заведённом таймере, поэтому смена значения
/// обязана его перезавести — иначе новое «раз в минуту» вступает в силу только
/// после перезапуска приложения.
@MainActor
@Test func refreshIntervalFromSettingsAppliesWithoutRestart() {
    final class Box { var value = Settings.defaults }
    let box = Box()
    let provider = WeatherProvider(
        cacheURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("interval-\(UUID().uuidString).json"),
        settings: { box.value.weather },
        fetch: { _ in throw CancellationError() })
    provider.start()
    #expect(provider.timerInterval == Config.Weather.refreshInterval)

    box.value.weatherRefreshMinutes = 1
    provider.settingsChanged()
    #expect(provider.timerInterval == Config.secondsInMinute)
    provider.stop()
}

/// Порог устаревания тоже из настроек: при пороге в сутки трёхчасовая погода
/// свежая, при пороге в час — уже с пометкой.
@Test func staleThresholdFromSettingsDecidesTheAgeLabel() {
    let snapshot = try! #require(WeatherSnapshot.decode(
        Data(#"{"current":{"temperature_2m":5,"apparent_temperature":3,"weather_code":1,"wind_speed_10m":2}}"#.utf8),
        now: now))
    var patient = Settings.defaults
    patient.weatherStaleMinutes = 24 * 60
    #expect(snapshot.ageDescription(now: now.addingTimeInterval(3 * 3600),
                                    staleAfter: patient.weather.staleAfter) == nil)
    var strict = Settings.defaults
    strict.weatherStaleMinutes = 1
    #expect(snapshot.ageDescription(now: now.addingTimeInterval(3 * 3600),
                                    staleAfter: strict.weather.staleAfter) == "3 ч назад")
}

@MainActor
@Test func keepsCachedValueWhenNetworkFails() async throws {
    let cache = FileManager.default.temporaryDirectory
        .appendingPathComponent("weather-\(UUID().uuidString).json")
    let good = #"{"current":{"temperature_2m":5,"apparent_temperature":3,"weather_code":1,"wind_speed_10m":2}}"#

    let ok = WeatherProvider(cacheURL: cache, fetch: { _ in Data(good.utf8) })
    await ok.refresh()
    #expect(ok.snapshot?.celsius == 5)

    struct Boom: Error {}
    let broken = WeatherProvider(cacheURL: cache, fetch: { _ in throw Boom() })
    await broken.refresh()
    #expect(broken.snapshot?.celsius == 5)
}

@Test func freshDataHasNoAgeLabel() {
    let snapshot = try! #require(WeatherSnapshot.decode(
        Data(#"{"current":{"temperature_2m":5,"apparent_temperature":3,"weather_code":1,"wind_speed_10m":2}}"#.utf8),
        now: now))
    #expect(snapshot.ageDescription(now: now.addingTimeInterval(60)) == nil)
}

@Test func staleDataSaysHowOldItIsInDaysNotJustAClock() {
    // «14:32» у трёхдневной погоды читается как сегодняшняя. Возраст обязан
    // называть дни, иначе пометка не спасает от тихой лжи.
    let snapshot = try! #require(WeatherSnapshot.decode(
        Data(#"{"current":{"temperature_2m":5,"apparent_temperature":3,"weather_code":1,"wind_speed_10m":2}}"#.utf8),
        now: now))
    #expect(snapshot.ageDescription(now: now.addingTimeInterval(3 * 3600)) == "3 ч назад")
    #expect(snapshot.ageDescription(now: now.addingTimeInterval(3 * 86400)) == "3 дн назад")
}

@Test func rejectsCurrentBlockMissingALeafField() {
    let json = #"{"current":{"temperature_2m":5,"apparent_temperature":3,"weather_code":1}}"#
    #expect(WeatherSnapshot.decode(Data(json.utf8), now: now) == nil)
}

/// Подделка таймеров: считает заведённые и живые и умеет тикнуть за них.
///
/// Иначе «повторный `start()` не плодит таймеры» проверить нечем. Прежний тест
/// считал обращения к сети и утверждал `calls <= 2` при замеренной единице:
/// лишний таймер на пятнадцатиминутном интервале за время теста не тикает ни
/// разу, поэтому число обращений не менялось и со снятой защитой — тест был
/// зелёным на сломанном коде.
@MainActor
final class FakeRefreshTimers: RefreshTimers {
    /// Интервалы всех заведённых таймеров, по порядку.
    private(set) var intervals: [TimeInterval] = []
    private var alive: [ObjectIdentifier: @Sendable @MainActor () async -> Void] = [:]

    var scheduledCount: Int { intervals.count }
    var aliveCount: Int { alive.count }

    func schedule(every interval: TimeInterval,
                  tick: @escaping @Sendable @MainActor () async -> Void) -> RefreshTimer {
        intervals.append(interval)
        let handle = Handle(owner: self)
        alive[ObjectIdentifier(handle)] = tick
        return handle
    }

    /// Тик всех живых таймеров. Асинхронный, чтобы тест ДОЖДАЛСЯ обновления,
    /// а не надеялся, что порождённая задача успеет выполниться.
    func fireAll() async {
        for tick in alive.values { await tick() }
    }

    fileprivate func forget(_ handle: Handle) { alive[ObjectIdentifier(handle)] = nil }

    @MainActor
    final class Handle: RefreshTimer {
        private weak var owner: FakeRefreshTimers?
        init(owner: FakeRefreshTimers) { self.owner = owner }
        func cancel() { owner?.forget(self) }
    }
}

@MainActor
private func provider(timers: RefreshTimers,
                      fetch: @escaping (URL) async throws -> Data) -> WeatherProvider {
    WeatherProvider(cacheURL: FileManager.default.temporaryDirectory
        .appendingPathComponent("timers-\(UUID().uuidString).json"),
                    timers: timers,
                    fetch: fetch)
}

private func weatherJSON(_ celsius: Double) -> Data {
    Data(#"{"current":{"temperature_2m":\#(celsius),"apparent_temperature":3,"weather_code":1,"wind_speed_10m":2}}"#.utf8)
}

/// Второй `start()` обязан не заводить второго таймера: два независимых
/// обновления на одном интервале, без синхронизации между ними, — это гонка,
/// а первый таймер к тому же остался бы жить, и выключить его было бы нечем.
@Test @MainActor func secondStartDoesNotAddASecondTimer() async {
    let timers = FakeRefreshTimers()
    let weather = provider(timers: timers, fetch: { _ in weatherJSON(5) })

    weather.start()
    weather.start()

    #expect(timers.scheduledCount == 1)
    #expect(timers.aliveCount == 1)

    weather.stop()
    #expect(timers.aliveCount == 0)
}

/// Смена интервала в настройках перезаводит таймер, а не добавляет второй:
/// заведено два, а живёт по-прежнему один.
@Test @MainActor func changedIntervalReplacesTheTimerInsteadOfAddingOne() async {
    final class Box { var value = Settings.defaults }
    let box = Box()
    let timers = FakeRefreshTimers()
    let weather = WeatherProvider(
        cacheURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("timers-\(UUID().uuidString).json"),
        settings: { box.value.weather },
        timers: timers,
        fetch: { _ in weatherJSON(5) })

    weather.start()
    box.value.weatherRefreshMinutes = 1
    weather.settingsChanged()

    #expect(timers.scheduledCount == 2)
    #expect(timers.aliveCount == 1)
    #expect(timers.intervals == [Config.Weather.refreshInterval, Config.secondsInMinute])

    weather.stop()
    #expect(timers.aliveCount == 0)
}

/// Таймер обязан обновлять погоду. Без этой проверки «не плодить таймеры»
/// выполнялось бы и не заводя ни одного.
@Test @MainActor func timerTickIsWhatRefreshesTheWeather() async {
    let timers = FakeRefreshTimers()
    var answer = 1.0
    let weather = provider(timers: timers, fetch: { _ in weatherJSON(answer) })

    weather.start()
    // Отдаём управление немедленному обновлению из `start()`, чтобы дальше
    // единственным источником новых данных остался тик таймера.
    await Task.yield()
    await timers.fireAll()

    answer = 7
    await timers.fireAll()
    #expect(weather.snapshot?.celsius == 7)

    weather.stop()
}

@MainActor
@Test func hasNoSnapshotWhenThereIsNeitherNetworkNorCache() async {
    struct Boom: Error {}
    let provider = WeatherProvider(
        cacheURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("нет-\(UUID().uuidString).json"),
        fetch: { _ in throw Boom() })
    await provider.refresh()
    #expect(provider.snapshot == nil)
}

// MARK: - Отказ обязан быть виден в логе

/// Каталог под кэш погоды: нужен целиком, чтобы посмотреть, что рядом с
/// испорченным файлом появился отложенный.
private func weatherRoot() -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("weather-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// Сети нет. Прежде это был молчаливый выход: погода не обновлялась, в
/// интерфейсе висело «3 дн назад», а в логе за трое суток не было ни строчки —
/// искать причину было не по чему.
@MainActor
@Test func networkFailureSaysSoInTheLog() async {
    struct NoRoute: Error {}
    var said: [String] = []
    let weather = WeatherProvider(cacheURL: weatherRoot().appendingPathComponent("weather.json"),
                                  fetch: { _ in throw NoRoute() },
                                  log: { said.append($0) })
    await weather.refresh()
    #expect(weather.snapshot == nil)
    #expect(said.count == 1)
    #expect(said.first?.contains("NoRoute") == true)
}

/// Прокси отдал HTML-заглушку вместо JSON. Отдельный исход: лечится он не
/// «проверьте сеть», а «посмотрите, что подставляет прокси», — поэтому в логе
/// обязано быть видно начало того, что пришло.
@MainActor
@Test func proxyStubSaysWhatCameInsteadOfWeather() async throws {
    let stub = "<html><head><title>Доступ ограничен</title></head></html>"
    var said: [String] = []
    let weather = WeatherProvider(cacheURL: weatherRoot().appendingPathComponent("weather.json"),
                                  fetch: { _ in Data(stub.utf8) },
                                  log: { said.append($0) })
    await weather.refresh()
    #expect(weather.snapshot == nil)
    let message = try #require(said.first)
    #expect(message.contains("<html>"))
    #expect(message.contains("Доступ ограничен"))
}

/// Мусорное значение — третий, тоже отдельный исход: ответ пришёл и разобрался,
/// но 900 градусов не бывает. «Проверьте сеть» тут сбило бы с толку.
@MainActor
@Test func implausibleAnswerIsLoggedAsBrokenAnswerNotAsNoNetwork() async throws {
    let hot = #"{"current":{"temperature_2m":900,"apparent_temperature":10,"weather_code":1,"wind_speed_10m":5}}"#
    var said: [String] = []
    let weather = WeatherProvider(cacheURL: weatherRoot().appendingPathComponent("weather.json"),
                                  fetch: { _ in Data(hot.utf8) },
                                  log: { said.append($0) })
    await weather.refresh()
    #expect(weather.snapshot == nil)
    let message = try #require(said.first)
    #expect(message.contains("900"))
}

/// Три исхода обязаны быть различимы. Раньше все три давали один и тот же
/// молчаливый `return`, и по логу нельзя было понять, что именно сломалось.
@Test func threeWaysOfFailingReadDifferently() {
    let stub = WeatherSnapshot.decoded(Data("<html>заглушка</html>".utf8), now: now)
    let hot = WeatherSnapshot.decoded(
        Data(#"{"current":{"temperature_2m":900,"apparent_temperature":10,"weather_code":1,"wind_speed_10m":5}}"#.utf8),
        now: now)
    guard case .failure(let stubProblem) = stub, case .failure(let hotProblem) = hot else {
        Issue.record("оба ответа обязаны быть отказом")
        return
    }
    #expect(stubProblem != hotProblem)
    #expect(stubProblem.message != hotProblem.message)
    #expect(stubProblem.message.contains("заглушка"))
    #expect(hotProblem.message.contains("900"))
}

/// Испорченный файл кэша откладывается в сторону, а не перечитывается и молча
/// выбрасывается при каждом запуске. Механизм общий с историей и полкой —
/// `StateFile`, а не своя пара `try?`.
@MainActor
@Test func brokenCacheIsSetAsideNotSilentlyRereadForever() throws {
    let dir = weatherRoot()
    let file = dir.appendingPathComponent("weather.json")
    try Data("{половина фай".utf8).write(to: file)

    let weather = WeatherProvider(cacheURL: file, fetch: { _ in throw CancellationError() },
                                  log: { _ in })
    #expect(weather.snapshot == nil)

    #expect(FileManager.default.fileExists(atPath: file.path) == false)
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path)
        .contains { $0.hasPrefix("weather.json.broken-") })
}

/// Кэш, который приложение записало само, обязан читаться обратно — иначе
/// откладывание в сторону срабатывало бы на собственном же файле при каждом
/// запуске, и погода начинала бы с нуля после каждого выхода.
@MainActor
@Test func cacheWrittenByAppIsReadBackOnNextLaunch() async throws {
    let file = weatherRoot().appendingPathComponent("weather.json")
    let first = WeatherProvider(cacheURL: file, fetch: { _ in weatherJSON(5) }, log: { _ in })
    await first.refresh()
    #expect(first.snapshot?.celsius == 5)

    var said: [String] = []
    let second = WeatherProvider(cacheURL: file, fetch: { _ in throw CancellationError() },
                                 log: { said.append($0) })
    #expect(second.snapshot?.celsius == 5)
    #expect(FileManager.default.fileExists(atPath: file.path))
}

/// Не записавшийся кэш — тоже отказ, и молчать о нём нельзя: погода после
/// такого живёт только в памяти и пропадает при выходе.
@MainActor
@Test func cacheThatCannotBeWrittenSaysSoInTheLog() async {
    // Путь внутрь файла: каталог по нему не создать, запись обязана провалиться.
    let impossible = URL(fileURLWithPath: "/dev/null/погода/weather.json")
    var said: [String] = []
    let weather = WeatherProvider(cacheURL: impossible, fetch: { _ in weatherJSON(5) },
                                 log: { said.append($0) })
    await weather.refresh()
    #expect(weather.snapshot?.celsius == 5)
    #expect(said.count == 1)
}

// MARK: - Прогноз на ближайшие часы

@Test func decodesUpcomingHoursDroppingTheCurrentOneAndImplausiblePoints() throws {
    // Владелец попросил показывать не только текущую погоду, а и то, что
    // впереди. Первый час прогноза дублирует уже показанный текущий — его
    // не нужно повторять; а откровенный сбой ответа (900°) фильтруется тем
    // же правилом, что и текущая температура, а не роняет весь прогноз.
    let url = try #require(Bundle.module.url(forResource: "Fixtures/open-meteo", withExtension: "json"))
    let snapshot = try #require(WeatherSnapshot.decode(try Data(contentsOf: url), now: now))
    #expect(snapshot.upcoming.map(\.hour) == ["17:00", "18:00", "19:00"])
    #expect(snapshot.upcoming.map(\.celsius) == [20.5, 19.1, 18.0])
    #expect(snapshot.upcoming.map(\.code) == [1, 1, 0])
}

@Test func missingHourlyBlockIsAnEmptyForecastNotAFailure() {
    // Прогноз необязателен: старый кэш или ответ без параметра `hourly`
    // (мало ли кто его уберёт) не должен ронять декодирование целиком —
    // текущая погода важнее прогноза на потом.
    let json = #"{"current":{"temperature_2m":5,"apparent_temperature":3,"weather_code":1,"wind_speed_10m":2}}"#
    let snapshot = try! #require(WeatherSnapshot.decode(Data(json.utf8), now: now))
    #expect(snapshot.upcoming.isEmpty)
}

@Test func mismatchedHourlyArrayLengthsAreTruncatedNotCrashed() {
    // Три массива обязаны идти вместе; рассинхрон (сеть оборвалась посреди
    // ответа) не должен читать за пределы самого короткого из них.
    let json = #"""
    {"current":{"temperature_2m":5,"apparent_temperature":3,"weather_code":1,"wind_speed_10m":2},
     "hourly":{"time":["2026-08-21T16:00","2026-08-21T17:00","2026-08-21T18:00"],
               "temperature_2m":[5,6],
               "weather_code":[1,1,1]}}
    """#
    let snapshot = try! #require(WeatherSnapshot.decode(Data(json.utf8), now: now))
    #expect(snapshot.upcoming.map(\.hour) == ["17:00"])
}

@Test func requestURLAsksForHourlyForecast() {
    let url = WeatherProvider.requestURL(for: .defaults).absoluteString
    #expect(url.contains("hourly=temperature_2m%2Cweather_code")
            || url.contains("hourly=temperature_2m,weather_code"))
    #expect(url.contains("forecast_hours=\(Config.Weather.forecastHours)"))
}
