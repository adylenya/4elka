import Foundation

/// Живой периодический таймер: пока его не выключили — тикает. Выключить его
/// можно только этим объектом, поэтому терять ссылку на него нельзя.
@MainActor
public protocol RefreshTimer: AnyObject {
    func cancel()
}

/// Чем заводится периодический таймер. Отдельный тип, а не `Timer` прямо в
/// `WeatherProvider`, ровно из-за проверяемости.
///
/// «Повторный `start()` не плодит таймеры» — это утверждение про КОЛИЧЕСТВО
/// заведённых таймеров, и измерить его через число обращений к сети нельзя:
/// лишний таймер на пятнадцатиминутном интервале за время теста не тикнет ни
/// разу. Тест, считавший обращения, оставался зелёным и со снятой защитой, то
/// есть закреплял дефект вместо требования. С этим типом подделка в тесте
/// считает таймеры прямо и может тикнуть за них.
public protocol RefreshTimers: Sendable {
    /// `tick` асинхронный, чтобы тест мог ДОЖДАТЬСЯ обновления, а не надеяться,
    /// что порождённая задача успеет выполниться до конца проверки.
    @MainActor
    func schedule(every interval: TimeInterval,
                  tick: @escaping @Sendable @MainActor () async -> Void) -> RefreshTimer
}

/// Настоящие таймеры на главном цикле выполнения.
public struct SystemRefreshTimers: RefreshTimers {
    public init() {}

    @MainActor
    public func schedule(every interval: TimeInterval,
                         tick: @escaping @Sendable @MainActor () async -> Void) -> RefreshTimer {
        SystemRefreshTimer(interval: interval, tick: tick)
    }
}

/// Обёртка над `Timer`: держит его и гасит по `cancel()`. Отдельным объектом,
/// потому что незаглушённый `Timer` продолжает тикать сам по себе, даже когда
/// хозяин про него забыл, — так и выглядел бы наслоившийся второй таймер.
@MainActor
final class SystemRefreshTimer: RefreshTimer {
    private var timer: Timer?

    init(interval: TimeInterval, tick: @escaping @Sendable @MainActor () async -> Void) {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in await tick() }
        }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }
}
