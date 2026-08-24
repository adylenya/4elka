import Foundation

/// Текущая погода из Open-Meteo (без ключа) для координат из настроек.
/// Разрешение на геолокацию не запрашивается и не нужно — координаты человек
/// выбирает сам, городом из справочника или числами.
///
/// Настройки читаются замыканием, а не копируются при создании: выбранный
/// город, интервал обновления и порог устаревания должны доходить до погоды
/// сразу, а не после перезапуска приложения.
///
/// Сети нет — остаёмся на кэше на диске (через `StateFile`), а не показываем
/// ноль или прочерк: вчерашние 20 градусов честнее, чем ничего.
///
/// Молчать про отказ при этом нельзя. Три исхода — сети нет, прокси отдал
/// страницу-заглушку, пришло 900 градусов — раньше давали один и тот же
/// молчаливый выход: погода не обновлялась, в интерфейсе тихо висело
/// «3 дн назад», а в логе за трое суток не было ни строчки. Теперь каждый
/// исход называет себя, и куда ругаться — параметр, иначе «об этом сказано в
/// лог» нечем проверить тестом.
@MainActor
public final class WeatherProvider: ObservableObject {
    @Published public private(set) var snapshot: WeatherSnapshot?

    /// Кэш на диске. Тот же `StateFile`, что у истории и полки: испорченный
    /// файл откладывается в сторону с записью в лог, а не перечитывается и
    /// молча выбрасывается при каждом запуске.
    private let cache: StateFile
    private let settings: () -> WeatherSettings
    private let timers: RefreshTimers
    private let fetch: (URL) async throws -> Data
    private let log: (String) -> Void
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
                },
                log: @escaping (String) -> Void = { NSLog("4elka: %@", $0) }) {
        self.cache = StateFile(fileURL: cacheURL, subject: "кэш погоды")
        self.settings = settings
        self.timers = timers
        self.fetch = fetch
        self.log = log
        snapshot = cache.read(WeatherSnapshot.self)
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
            .init(name: "hourly", value: "temperature_2m,weather_code"),
            .init(name: "forecast_hours", value: String(Config.Weather.forecastHours)),
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
    /// чем показать вчерашние 20 градусов. Но каждый отказ называет себя в логе:
    /// иначе погода, не обновляющаяся месяц, выглядит как «иногда устаревает».
    public func refresh() async {
        // Без этого замка медленный старый ответ мог завершиться позже быстрого
        // нового и молча перезаписать свежие данные устаревшими.
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let data: Data
        do {
            data = try await fetch(requestURL)
        } catch {
            // Хост в сообщении не для красоты: по нему видно, что запрос вообще
            // ушёл туда, куда собирались, — а с прокси это не самоочевидно.
            log("погода не получена от \(requestURL.host ?? requestURL.absoluteString): "
                + "\(String(describing: error))")
            return
        }

        switch WeatherSnapshot.decoded(data, now: Date()) {
        case .failure(let problem):
            log(problem.message)
        case .success(let fresh):
            snapshot = fresh
            save(fresh)
        }
    }

    /// Незаписавшийся кэш — тоже отказ: погода после него живёт только в памяти
    /// и пропадает при выходе.
    private func save(_ fresh: WeatherSnapshot) {
        do {
            try cache.write(fresh)
        } catch {
            log("кэш погоды не записан, данные останутся только в памяти: "
                + "\(String(describing: error))")
        }
    }
}
