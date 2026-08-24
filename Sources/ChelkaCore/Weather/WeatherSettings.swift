import Foundation

/// Что погоде нужно из настроек: куда смотреть, как часто спрашивать и с какого
/// возраста считать данные устаревшими.
///
/// Отдельный тип, а не четыре аргумента: значения ходят вместе, и координаты,
/// разъехавшиеся с названием города, уже были дефектом. Значения по умолчанию
/// берутся из `Config` — он остаётся источником истины, а настройки его
/// перекрывают.
public struct WeatherSettings: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let refreshInterval: TimeInterval
    /// С какого возраста данные показываются с пометкой «столько-то назад».
    public let staleAfter: TimeInterval

    public init(latitude: Double, longitude: Double,
                refreshInterval: TimeInterval, staleAfter: TimeInterval) {
        self.latitude = latitude
        self.longitude = longitude
        self.refreshInterval = refreshInterval
        self.staleAfter = staleAfter
    }

    public static let defaults = WeatherSettings(
        latitude: Config.Weather.latitude,
        longitude: Config.Weather.longitude,
        refreshInterval: Config.Weather.refreshInterval,
        staleAfter: Config.Weather.staleAfter)
}
