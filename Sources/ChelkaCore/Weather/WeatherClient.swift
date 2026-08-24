import Foundation

/// Текущая погода из Open-Meteo (без ключа) для координат из настроек.
/// Разрешение на геолокацию не запрашивается и не нужно — координаты человек
/// выбирает сам, городом из справочника или числами.
///
/// Настройки читаются замыканием, а не копируются при создании: выбранный
/// город, интервал обновления и порог устаревания должны доходить до погоды
/// сразу, а не после перезапуска приложения.
///
/// Сети нет — остаёмся на кэше на диске (через `AtomicFile`), а не показываем
/// ноль или прочерк: вчерашние 20 градусов честнее, чем ничего.
@MainActor
public final class WeatherProvider: ObservableObject {
    @Published public private(set) var snapshot: WeatherSnapshot?

    private let cacheURL: URL
    private let settings: () -> WeatherSettings
    private let timers: RefreshTimers
    private let fetch: (URL) async throws -> Data
    private var timer: RefreshTimer?
    /// С каким интервалом заведён таймер. Нужно, чтобы поймать смену интервала
    /// в настройках: без этого «раз в минуту» вступало бы в силу только после
    /// перезапуска приложения.
    private(set) var timerInterval: TimeInterval?
    private var isRefreshing = false

    /// `timers` — чем заводится периодический таймер. Параметром, а не `Timer`
    /// внутри: только так проверяется, что повторный `start()` не заводит
    /// второго таймера. Подробнее — в `RefreshTimers`.
    public init(cacheURL: URL,
                settings: @escaping () -> WeatherSettings = { .defaults },
                timers: RefreshTimers = SystemRefreshTimers(),
                fetch: @escaping (URL) async throws -> Data = { url in
                    try await URLSession.shared.data(from: url).0
                }) {
        self.cacheURL = cacheURL
        self.settings = settings
        self.timers = timers
        self.fetch = fetch
        snapshot = Self.loadCache(cacheURL)
    }

    /// Текущие настройки погоды. Отдаются наружу, чтобы вьюхе не приходилось
    /// таскать те же значения вторым параметром: возраст данных считается по
    /// порогу из настроек, и порог обязан быть один и тот же у обоих.
    public var current: WeatherSettings { settings() }

    /// Запрос — чистая функция от настроек: так его видно в тесте, и так он не
    /// зависит от того, что сейчас лежит в файле настроек.
    ///
    /// `nonisolated`, потому что `self` она не трогает: изоляция всего класса на
    /// главный актор ей не нужна, а тест зовёт её синхронно.
    public nonisolated static func requestURL(for settings: WeatherSettings) -> URL {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(settings.latitude)),
            .init(name: "longitude", value: String(settings.longitude)),
            .init(name: "current",
                  value: "temperature_2m,apparent_temperature,weather_code,wind_speed_10m"),
            .init(name: "timezone", value: Config.timezone),
        ]
        return components.url!
    }

    public var requestURL: URL { Self.requestURL(for: settings()) }

    public func start() {
        // Повторный вызов иначе завёл бы второй таймер: два независимых
        // обновления на одном интервале, без всякой синхронизации между ними.
        guard timer == nil else { return }
        Task { await refresh() }
        schedule(interval: settings().refreshInterval)
    }

    public func stop() {
        timer?.cancel()
        timer = nil
        timerInterval = nil
    }

    /// Настройки изменились. Интервал обновления живёт в таймере, а таймер уже
    /// заведён — поэтому его надо перезавести, иначе новое значение вступит в
    /// силу только после перезапуска приложения.
    ///
    /// Координаты перезавода не требуют: их читает сам запрос при каждом
    /// обновлении. Но раз город сменился, ждать четверть часа незачем.
    public func settingsChanged() {
        guard timer != nil else { return }
        guard settings().refreshInterval != timerInterval else { return }
        schedule(interval: settings().refreshInterval)
        Task { await refresh() }
    }

    /// Прежний таймер гасится ДО того, как заводится новый: иначе он продолжит
    /// тикать сам по себе, ссылку на него уже никто не держит, и выключить его
    /// будет нечем.
    private func schedule(interval: TimeInterval) {
        timer?.cancel()
        timerInterval = interval
        timer = timers.schedule(every: interval) { [weak self] in
            await self?.refresh()
        }
    }

    /// Сети нет — остаёмся на кэше. Показывать ноль или пустоту было бы хуже,
    /// чем показать вчерашние 20 градусов.
    public func refresh() async {
        // Без этого замка медленный старый ответ мог завершиться позже быстрого
        // нового и молча перезаписать свежие данные устаревшими.
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        guard let data = try? await fetch(requestURL),
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
