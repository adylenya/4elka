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

@Test @MainActor func startIsIdempotentAndDoesNotStackTimers() async {
    var calls = 0
    let provider = WeatherProvider(
        cacheURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("idem-\(UUID().uuidString).json"),
        fetch: { _ in
            calls += 1
            return Data(#"{"current":{"temperature_2m":5,"apparent_temperature":3,"weather_code":1,"wind_speed_10m":2}}"#.utf8)
        })
    provider.start()
    provider.start()
    await provider.refresh()
    #expect(calls <= 2)
    provider.stop()
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
