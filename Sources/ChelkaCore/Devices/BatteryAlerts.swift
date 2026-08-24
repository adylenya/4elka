import Foundation

public struct BatteryAlert: Equatable, Sendable {
    public enum Level: Equatable, Sendable { case low, high, full }

    public let deviceName: String
    public let percent: Int
    public let level: Level

    public init(deviceName: String, percent: Int, level: Level) {
        self.deviceName = deviceName
        self.percent = percent
        self.level = level
    }

    public var activityEvent: ActivityEvent {
        switch level {
        case .low:
            return ActivityEvent(kind: .battery, title: "\(deviceName): \(percent)%",
                                 subtitle: "заряд на исходе")
        case .high:
            return ActivityEvent(kind: .battery, title: "\(deviceName): \(percent)%",
                                 subtitle: "можно отключать")
        case .full:
            return ActivityEvent(kind: .battery, title: "\(deviceName) заряжен",
                                 subtitle: "отключай")
        }
    }
}

/// Пороги, на которых выезжают карточки о заряде.
///
/// Отдельный тип, а не чтение `Config` изнутри: человек крутит эти три числа в
/// настройках, и без параметра раздел «Заряд» в окне настроек был бы мёртвой
/// крутилкой. Значения из `Config` остаются значениями по умолчанию.
public struct BatteryThresholds: Equatable, Sendable {
    public let low: Int
    public let high: Int
    /// «Заряжен». В настройках его нет: сотня — это сотня.
    public let full: Int
    /// Насколько заряд должен отойти от порога, чтобы правило снова взвелось.
    public let hysteresis: Int

    public init(low: Int, high: Int, full: Int, hysteresis: Int) {
        self.low = low
        self.high = high
        self.full = full
        self.hysteresis = hysteresis
    }

    public static let defaults = BatteryThresholds(
        low: Config.Battery.lowThreshold,
        high: Config.Battery.highThreshold,
        full: Config.Battery.fullThreshold,
        hysteresis: Config.Battery.hysteresis)
}

/// Срабатывание на пересечении порога, а не по условию «ниже порога»:
/// иначе на 19% карточка выезжала бы при каждом опросе, то есть раз в минуту.
public struct BatteryAlerts: Equatable, Sendable {
    private struct Armed: Equatable, Sendable {
        var lowArmed: Bool
        var highArmed: Bool
        var fullArmed: Bool
        /// Откуда пришло устройство. По источнику решается, забывать ли его
        /// состояние, когда устройства в опросе нет: источник ответил — значит
        /// устройство отключили, источник молчит — значит мы просто не знаем.
        var source: DeviceCharge.Source
    }

    private let armed: [String: Armed]

    public init() { armed = [:] }
    private init(armed: [String: Armed]) { self.armed = armed }

    public func evaluating(_ poll: DevicePoll,
                           thresholds: BatteryThresholds = .defaults)
        -> (BatteryAlerts, [BatteryAlert]) {
        let low = thresholds.low
        let high = thresholds.high
        let gap = thresholds.hysteresis

        // Состояние устройств, чей источник в этом опросе не ответил, переносим
        // как есть: сорвавшаяся утилита неотличима от отключённого устройства
        // по одному лишь отсутствию в списке, а забыть взведение по её провалу
        // значит выдать ту же карточку второй раз на том же заряде.
        var nextArmed = armed.filter { !poll.answered.contains($0.value.source) }
        var fired: [BatteryAlert] = []

        for device in poll.devices {
            // Незнакомое устройство считается взведённым, чтобы первый же
            // замер ниже порога дал уведомление.
            var state = armed[device.name]
                ?? Armed(lowArmed: true, highArmed: true, fullArmed: true, source: device.source)
            state.source = device.source

            if device.percent < low, state.lowArmed {
                fired.append(BatteryAlert(deviceName: device.name, percent: device.percent, level: .low))
                state.lowArmed = false
            } else if device.percent >= low + gap {
                state.lowArmed = true
            }

            if device.isCharging, device.percent >= high, state.highArmed {
                fired.append(BatteryAlert(deviceName: device.name, percent: device.percent, level: .high))
                state.highArmed = false
            } else if device.percent < high - gap {
                state.highArmed = true
            }

            let full = thresholds.full
            // Кабель обязателен, как и на верхнем пороге: «заряжен, отключай»
            // без кабеля советует отключить то, что и так отключено. Так
            // выглядел каждый холодный старт на полной батарее.
            if device.isCharging, device.percent >= full, state.fullArmed {
                fired.append(BatteryAlert(deviceName: device.name, percent: full, level: .full))
                state.fullArmed = false
                // «Заряжен» и «уже много» — про одно и то же событие. Устройство,
                // впервые увиденное сразу на сотне при зарядке, иначе выдало бы две
                // карточки подряд об одном и том же.
                fired.removeAll { $0.deviceName == device.name && $0.level == .high }
            } else if device.percent < full - gap {
                state.fullArmed = true
            }

            nextArmed[device.name] = state
        }

        return (BatteryAlerts(armed: nextArmed), fired)
    }
}
