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
    ///
    /// Отказ — не `nil`, а названная причина: «вместо погоды пришла страница»
    /// и «пришло 900 градусов» лечатся по-разному, и в логе их обязано быть
    /// видно по отдельности. `nil` на оба исхода однажды и превратил обрыв сети,
    /// заглушку прокси и мусорный ответ в один молчаливый выход.
    public static func decoded(_ data: Data,
                               now: Date) -> Result<WeatherSnapshot, WeatherResponseProblem> {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            return .failure(.notWeatherAnswer(bytes: data.count, beginning: preview(of: data)))
        }
        let c = response.current
        guard Config.Weather.plausibleCelsius.contains(c.temperature_2m),
              Config.Weather.plausibleCelsius.contains(c.apparent_temperature) else {
            return .failure(.implausibleTemperature(celsius: c.temperature_2m,
                                                    feelsLike: c.apparent_temperature))
        }
        return .success(WeatherSnapshot(celsius: c.temperature_2m,
                                        feelsLike: c.apparent_temperature,
                                        windKph: c.wind_speed_10m,
                                        code: c.weather_code,
                                        observedAt: now))
    }

    /// Тем, кому причина отказа не нужна.
    public static func decode(_ data: Data, now: Date) -> WeatherSnapshot? {
        try? decoded(data, now: now).get()
    }

    /// Начало ответа для лога. За прокси на месте JSON лежит HTML-заглушка, и
    /// увидеть её первые слова — единственный способ понять это по логу.
    /// Ответ обрезается и склеивается в одну строку: страница целиком в логе не
    /// нужна, а её переводы строк превратили бы одну запись в десяток.
    private static func preview(of data: Data) -> String {
        let text = String(decoding: data.prefix(Config.Weather.previewBytes), as: UTF8.self)
        let squeezed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return squeezed.isEmpty ? "(пусто)" : squeezed
    }

    public var summary: String { "\(Int(celsius.rounded()))°" }

    /// Возраст данных человеческими словами. Часы с минутами тут не годятся:
    /// «14:32» у трёхдневной погоды читается как сегодняшняя, если сейчас
    /// примерно тот же час — то есть это тихая ложь, а не пометка. Отдельная
    /// чистая функция, потому что именно её и надо проверять тестом.
    ///
    /// Порог устаревания приходит параметром: человек крутит его в настройках,
    /// а значение из `Config` — только значение по умолчанию.
    public func ageDescription(now: Date,
                               staleAfter: TimeInterval = Config.Weather.staleAfter) -> String? {
        let seconds = now.timeIntervalSince(observedAt)
        guard seconds >= staleAfter else { return nil }
        let hours = Int(seconds / 3600)
        if hours < 24 { return "\(hours) ч назад" }
        return "\(hours / 24) дн назад"
    }

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
