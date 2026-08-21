import Foundation

/// Текущая погода из Open-Meteo (без ключа) для координат Астаны из `Config`.
/// Разрешение на геолокацию не запрашивается и не нужно — координаты зашиты.
///
/// Сети нет — остаёмся на кэше на диске (через `AtomicFile`), а не показываем
/// ноль или прочерк: вчерашние 20 градусов честнее, чем ничего.
@MainActor
public final class WeatherProvider: ObservableObject {
    @Published public private(set) var snapshot: WeatherSnapshot?

    private let cacheURL: URL
    private let fetch: (URL) async throws -> Data
    private var timer: Timer?
    private var isRefreshing = false

    public init(cacheURL: URL,
                fetch: @escaping (URL) async throws -> Data = { url in
                    try await URLSession.shared.data(from: url).0
                }) {
        self.cacheURL = cacheURL
        self.fetch = fetch
        snapshot = Self.loadCache(cacheURL)
    }

    public static var requestURL: URL {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(Config.Weather.latitude)),
            .init(name: "longitude", value: String(Config.Weather.longitude)),
            .init(name: "current",
                  value: "temperature_2m,apparent_temperature,weather_code,wind_speed_10m"),
            .init(name: "timezone", value: Config.timezone),
        ]
        return components.url!
    }

    public func start() {
        // Повторный вызов иначе завёл бы второй таймер: два независимых
        // обновления на одном интервале, без всякой синхронизации между ними.
        guard timer == nil else { return }
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: Config.Weather.refreshInterval,
                                     repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    public func stop() { timer?.invalidate(); timer = nil }

    /// Сети нет — остаёмся на кэше. Показывать ноль или пустоту было бы хуже,
    /// чем показать вчерашние 20 градусов.
    public func refresh() async {
        // Без этого замка медленный старый ответ мог завершиться позже быстрого
        // нового и молча перезаписать свежие данные устаревшими.
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        guard let data = try? await fetch(Self.requestURL),
              let fresh = WeatherSnapshot.decode(data, now: Date()) else { return }
        snapshot = fresh
        do {
            try AtomicFile.write(try JSONEncoder().encode(fresh), to: cacheURL)
        } catch {
            NSLog("4elka: не удалось сохранить кэш погоды: %@", String(describing: error))
        }
    }

    private static func loadCache(_ url: URL) -> WeatherSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WeatherSnapshot.self, from: data)
    }
}
