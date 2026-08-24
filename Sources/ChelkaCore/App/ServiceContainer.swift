import AppKit
import Foundation

/// Долгоживущие подсистемы раскрытой панели в одном месте: плеер, заряды
/// устройств, погода и память порогов заряда.
///
/// Зачем отдельный тип. Плеер, календарь, погода и заряды были написаны,
/// покрыты тестами и не подключены ни к чему — каждая задача считала подключение
/// чужой работой. Собирать их по месту в `AppDelegate`, где уже больше трёхсот
/// строк, значило бы сделать его нечитаемым; а главное — тогда «плеер
/// запускается один раз» и «мост гасится при выходе» жили бы в разных концах
/// делегата и проверить их было бы нечем.
///
/// Настройки читаются замыканием, а не копируются при создании: правка в
/// открытом окне настроек обязана доходить до подсистем без перезапуска.
@MainActor
public final class ServiceContainer {
    public let media: MediaCoordinator
    public let devices: DevicesProvider
    public let weather: WeatherProvider

    /// Тот же объект, что внутри координатора. Держим ссылку ради одного:
    /// поток адаптера — долгоживущий процесс perl, и гасить его при выходе
    /// обязан кто-то явно. Замерено: процесс переживает смерть хозяина и
    /// умирает лишь при следующей попытке записи в закрытую трубу — то есть
    /// висит, пока не сменится трек, а на паузе неограниченно долго.
    private let mediaSource: MediaSource
    private let settings: () -> Settings
    private let submitActivity: (ActivityEvent) -> Void

    /// Память порогов заряда. Обязана переживать замеры: опрос идёт раз в
    /// минуту, и без памяти карточка «заряд на исходе» выезжала бы каждую
    /// минуту до самой розетки.
    private var alerts = BatteryAlerts()

    /// Запущены ли подсистемы. Повторный запуск поднял бы второй процесс
    /// адаптера, а повторное гашение дёргало бы очередь супервизора зря.
    private var isRunning = false

    public init(mediaSource: MediaSource,
                devices: DevicesProvider,
                weather: WeatherProvider,
                settings: @escaping () -> Settings,
                submitActivity: @escaping (ActivityEvent) -> Void) {
        self.mediaSource = mediaSource
        self.devices = devices
        self.weather = weather
        self.settings = settings
        self.submitActivity = submitActivity
        self.media = MediaCoordinator(source: mediaSource, submitActivity: submitActivity)
    }

    /// Настоящая сборка: адаптер ищется на диске, заряды читаются системными
    /// утилитами, погода кэшируется в каталоге приложения.
    public static func live(settings: @escaping () -> Settings,
                            submitActivity: @escaping (ActivityEvent) -> Void,
                            log: @escaping @Sendable (String) -> Void = {
                                NSLog("4elka: %@", $0)
                            }) -> ServiceContainer {
        ServiceContainer(mediaSource: mediaSource(log: log),
                         devices: DevicesProvider(),
                         weather: WeatherProvider(cacheURL: AppPaths.weather,
                                                  settings: { settings().weather }),
                         settings: settings,
                         submitActivity: submitActivity)
    }

    /// Источник состояния плеера: настоящий мост, если адаптер найден, и
    /// честная заглушка, если нет.
    ///
    /// Причина отказа обязана попасть в лог: плеер, умирающий молча, выглядит
    /// как «иногда не работает», и таким он и был — подсистема живая, панель
    /// пустая, в логе ни строчки.
    static func mediaSource(location: AdapterLocation = AdapterPaths.locate(),
                            log: @escaping @Sendable (String) -> Void) -> MediaSource {
        switch location {
        case .found(let paths, let source):
            log("адаптер плеера взят из \(source.title): \(paths.script.path)")
            return MediaRemoteBridge(paths: paths)
        case .missing(let problem):
            log(problem.message)
            return MissingMediaSource()
        }
    }

    /// Плеер поднимается ЗДЕСЬ, один раз при старте приложения, а не при каждом
    /// раскрытии панели: панель раскрывается несколько раз в минуту, и это
    /// означало бы новый процесс perl на каждое раскрытие.
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        media.start()
        devices.onUpdate = { [weak self] poll in self?.handleDevices(poll) }
        devices.start()
        weather.start()
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        mediaSource.stop()
        devices.stop()
        weather.stop()
    }

    /// Что нужно применить сразу, а не при следующем событии: интервал
    /// обновления погоды живёт в уже заведённом таймере.
    public func settingsChanged() {
        weather.settingsChanged()
    }

    /// Новый замер зарядов. `internal`, а не приватный, ровно затем, чтобы
    /// проверить тестом главное: память порогов переживает замеры, а скрытый
    /// настройкой айфон не выдаёт карточек.
    func handleDevices(_ poll: DevicePoll) {
        // Отбор «что человек согласился видеть» применяется к устройствам, но не
        // к списку ответивших источников: скрытый настройкой айфон не должен
        // выглядеть как сорвавшаяся утилита.
        let visible = DevicePoll(devices: visibleDevices(from: poll.devices),
                                 answered: poll.answered)
        let (next, fired) = alerts.evaluating(visible,
                                              thresholds: settings().batteryThresholds)
        alerts = next
        for alert in fired { submitActivity(alert.activityEvent) }
    }

    /// Заряды, которые человек согласился видеть. Один отбор и для списка в
    /// панели, и для карточек: два независимых решения однажды показали бы в
    /// списке то, о чём карточки молчат.
    func visibleDevices(from measured: [DeviceCharge]) -> [DeviceCharge] {
        DeviceList.visible(measured, showsPhone: settings().showsPhone)
    }

    /// Показывать ли айфон — для вьюхи списка зарядов. Читается при каждой
    /// отрисовке, поэтому тумблер в настройках доходит до панели сразу.
    public var showsPhone: Bool { settings().showsPhone }

    /// Что показывать в плеере — по той же причине читается при отрисовке.
    public var playerOptions: PlayerOptions { settings().playerOptions }
}
