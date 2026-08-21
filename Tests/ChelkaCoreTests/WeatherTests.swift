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

@MainActor
@Test func requestURLCarriesAstanaCoordinates() {
    let url = WeatherProvider.requestURL.absoluteString
    #expect(url.contains("latitude=51.1605"))
    #expect(url.contains("longitude=71.4704"))
    #expect(url.contains("Asia/Almaty"))
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
