import Foundation

/// Погода на момент наблюдения. Внешним данным (Open-Meteo) не доверяем:
/// значение вне разумного диапазона (`Config.Weather.plausibleCelsius`)
/// считается сбоем ответа, а не погодой, и не декодируется вовсе.
public struct WeatherSnapshot: Equatable, Codable, Sendable {
    public let celsius: Double
    public let feelsLike: Double
    public let windKph: Double
    public let code: Int
    public let observedAt: Date

    private struct Response: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let apparent_temperature: Double
            let weather_code: Int
            let wind_speed_10m: Double
        }
        let current: Current
    }

    /// Внешним данным не доверяем: ответ вне разумного диапазона считаем сбоем.
    public static func decode(_ data: Data, now: Date) -> WeatherSnapshot? {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        let c = response.current
        guard Config.Weather.plausibleCelsius.contains(c.temperature_2m),
              Config.Weather.plausibleCelsius.contains(c.apparent_temperature) else { return nil }
        return WeatherSnapshot(celsius: c.temperature_2m,
                               feelsLike: c.apparent_temperature,
                               windKph: c.wind_speed_10m,
                               code: c.weather_code,
                               observedAt: now)
    }

    public var summary: String { "\(Int(celsius.rounded()))°" }

    /// Коды WMO: 0 ясно, 1–3 переменная облачность, 45–48 туман,
    /// 51–67 дождь, 71–77 снег, 80–82 ливни, 95–99 гроза.
    public var symbol: String {
        switch code {
        case 0: return "sun.max"
        case 1...3: return "cloud.sun"
        case 45...48: return "cloud.fog"
        case 51...67: return "cloud.rain"
        case 71...77: return "cloud.snow"
        case 80...82: return "cloud.heavyrain"
        case 95...99: return "cloud.bolt.rain"
        default: return "cloud"
        }
    }
}
