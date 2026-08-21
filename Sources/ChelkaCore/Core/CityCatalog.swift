import Foundation

/// Город с координатами. В настройках человек выбирает город, а не вводит
/// широту и долготу руками.
public struct City: Equatable, Sendable, Identifiable {
    public let name: String
    public let latitude: Double
    public let longitude: Double

    public init(name: String, latitude: Double, longitude: Double) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }

    public var id: String { name }
}

/// Список городов зашит в приложение, а не спрашивается у сервиса геокодинга.
/// Причины две: поиск обязан работать без сети (настройки открывают и в
/// самолёте), и лишний сетевой запрос за одним названием того не стоит.
/// Города, которого нет в списке, задаются координатами вручную — поля
/// широты и долготы в настройках остаются.
public enum CityCatalog {
    /// Первым идёт город из `Config`: он же и по умолчанию.
    public static let all: [City] = [
        City(name: Config.Weather.cityName,
             latitude: Config.Weather.latitude,
             longitude: Config.Weather.longitude),
        City(name: "Алматы", latitude: 43.2389, longitude: 76.8897),
        City(name: "Шымкент", latitude: 42.3417, longitude: 69.5901),
        City(name: "Караганда", latitude: 49.8047, longitude: 73.1094),
        City(name: "Актобе", latitude: 50.2839, longitude: 57.1670),
        City(name: "Атырау", latitude: 47.0945, longitude: 51.9238),
        City(name: "Павлодар", latitude: 52.2873, longitude: 76.9674),
        City(name: "Усть-Каменогорск", latitude: 49.9481, longitude: 82.6279),
        City(name: "Костанай", latitude: 53.2144, longitude: 63.6246),
        City(name: "Бишкек", latitude: 42.8746, longitude: 74.5698),
        City(name: "Ташкент", latitude: 41.2995, longitude: 69.2401),
        City(name: "Тбилиси", latitude: 41.7151, longitude: 44.8271),
        City(name: "Москва", latitude: 55.7558, longitude: 37.6173),
        City(name: "Стамбул", latitude: 41.0082, longitude: 28.9784),
        City(name: "Дубай", latitude: 25.2048, longitude: 55.2708),
        City(name: "Берлин", latitude: 52.5200, longitude: 13.4050),
        City(name: "Кёльн", latitude: 50.9375, longitude: 6.9603),
        City(name: "Лондон", latitude: 51.5072, longitude: -0.1276),
        City(name: "Лиссабон", latitude: 38.7223, longitude: -9.1393),
        City(name: "Белград", latitude: 44.7866, longitude: 20.4489),
        City(name: "Тель-Авив", latitude: 32.0853, longitude: 34.7818),
        City(name: "Нью-Йорк", latitude: 40.7128, longitude: -74.0060),
        City(name: "Сан-Франциско", latitude: 37.7749, longitude: -122.4194),
        City(name: "Токио", latitude: 35.6762, longitude: 139.6503),
        City(name: "Сингапур", latitude: 1.3521, longitude: 103.8198),
        City(name: "Сидней", latitude: -33.8688, longitude: 151.2093),
    ]

    /// Поиск так, как человек печатает: без учёта регистра и без точек над
    /// «ё» — её на клавиатуре никто не набирает. Пустая строка — весь список,
    /// а не пустота: иначе поле поиска выглядело бы как сломанное.
    public static func search(_ query: String) -> [City] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return all }
        return all.filter {
            $0.name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}
