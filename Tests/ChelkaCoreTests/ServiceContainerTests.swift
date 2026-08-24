import Testing
import Foundation
@testable import ChelkaCore

/// Подсистемы, которые были написаны, покрыты тестами и никуда не подключены.
/// Здесь проверяется именно подключение: поток плеера поднимается ОДИН раз и
/// гасится при выходе, замер зарядов доходит до карточек, а память порогов
/// живёт между замерами.

@MainActor
private final class FakeSource: MediaSource {
    private var onState: (@MainActor (NowPlaying) -> Void)?
    private var onUnavailable: (@MainActor () -> Void)?
    private(set) var starts = 0
    private(set) var stops = 0

    func start(onState: @escaping @MainActor (NowPlaying) -> Void,
               onUnavailable: @escaping @MainActor () -> Void) {
        self.onState = onState
        self.onUnavailable = onUnavailable
        starts += 1
    }
    func stop() { stops += 1 }
    func send(_ command: MediaCommand) {}
    func emit(_ state: NowPlaying) { onState?(state) }
}

/// Ни одной живой системной команды: `system_profiler` и `pmset` в тестах
/// запускать нельзя — они занимают секунды и зависят от машины.
private struct SilentRunner: CommandRunning {
    func run(_ path: String, _ args: [String]) -> String? { nil }
}

@MainActor
private func makeContainer(settings: @escaping () -> Settings = { .defaults })
    -> (ServiceContainer, FakeSource, () -> [ActivityEvent]) {
    let source = FakeSource()
    var events: [ActivityEvent] = []
    let cache = FileManager.default.temporaryDirectory
        .appendingPathComponent("chelka-weather-\(UUID().uuidString).json")
    let container = ServiceContainer(
        mediaSource: source,
        devices: DevicesProvider(runner: SilentRunner()),
        weather: WeatherProvider(cacheURL: cache, fetch: { _ in throw CancellationError() }),
        settings: settings,
        submitActivity: { events.append($0) })
    return (container, source, { events })
}

private func charge(_ name: String, _ percent: Int, charging: Bool = false,
                    source: DeviceCharge.Source = .mac) -> DeviceCharge {
    DeviceCharge(name: name, percent: percent, isCharging: charging, source: source,
                 symbol: "laptopcomputer")
}

// MARK: - Поток плеера поднимается один раз и гасится при выходе

@MainActor
@Test func playerStreamStartsOnceEvenIfStartIsCalledAgain() {
    // Поток адаптера — долгоживущий процесс perl. Раскрытие панели происходит
    // несколько раз в минуту, и повторный запуск означал бы новый процесс на
    // каждое раскрытие. Отдельно: обработчик завершения умершего процесса уже
    // однажды гасил только что поднятый новый.
    let (container, source, _) = makeContainer()
    container.start()
    container.start()
    #expect(source.starts == 1)
    container.stop()
}

@MainActor
@Test func quittingStopsThePlayerStreamExactlyOnce() {
    // Замерено: процесс адаптера переживает смерть хозяина и умирает лишь при
    // следующей попытке записи в закрытую трубу — на паузе неограниченно долго.
    let (container, source, _) = makeContainer()
    container.start()
    container.stop()
    container.stop()
    #expect(source.stops == 1)
}

@MainActor
@Test func stopWithoutStartDoesNotTouchTheStream() {
    // Выход при сорвавшемся запуске: гасить нечего, и поднимать очередь
    // супервизора ради этого незачем.
    let (container, source, _) = makeContainer()
    container.stop()
    #expect(source.stops == 0)
}

// MARK: - Плеера нет вовсе

@MainActor
@Test func withoutAnAdapterThePlayerIsHonestlyUnavailable() {
    // Ни в ресурсах, ни в дереве сборки адаптера нет. Плеер обязан сказать это
    // словами: молчаливая смерть плеера уже была дефектом.
    let container = ServiceContainer(
        mediaSource: MissingMediaSource(),
        devices: DevicesProvider(runner: SilentRunner()),
        weather: WeatherProvider(cacheURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("chelka-weather-\(UUID().uuidString).json"),
                                 fetch: { _ in throw CancellationError() }),
        settings: { .defaults },
        submitActivity: { _ in })
    container.start()
    #expect(!container.media.isAvailable)
    #expect(PlayerPresence.make(isAvailable: container.media.isAvailable,
                                isEmpty: container.media.state.isEmpty) == .unavailable)
    container.stop()
}

// MARK: - Заряды доходят до карточек

@MainActor
@Test func lowChargeReachesTheCardQueue() {
    let (container, _, events) = makeContainer()
    container.handleDevices(.complete([charge("MacBook", Config.Battery.lowThreshold - 1)]))
    #expect(events().count == 1)
    #expect(events().first?.kind == .battery)
}

@MainActor
@Test func theSameReadingTwiceDoesNotGiveASecondCard() {
    // Опрос идёт раз в минуту. Если память порогов пересоздавать на каждый
    // замер, карточка «заряд на исходе» выезжала бы раз в минуту до розетки.
    let (container, _, events) = makeContainer()
    let low = charge("MacBook", Config.Battery.lowThreshold - 1)
    container.handleDevices(.complete([low]))
    container.handleDevices(.complete([low]))
    #expect(events().count == 1)
}

@MainActor
@Test func hiddenPhoneNeitherShowsUpNorFiresCards() {
    var settings = Settings.defaults
    settings.showsPhone = false
    let (container, _, events) = makeContainer(settings: { settings })
    let phone = charge("Айфон", Config.Battery.lowThreshold - 1, source: .phone)
    container.handleDevices(.complete([phone]))
    #expect(events().isEmpty)
    #expect(container.visibleDevices(from: [phone]).isEmpty)
}
