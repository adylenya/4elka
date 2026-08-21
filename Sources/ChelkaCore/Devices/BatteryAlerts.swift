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

/// Срабатывание на пересечении порога, а не по условию «ниже порога»:
/// иначе на 19% карточка выезжала бы при каждом опросе, то есть раз в минуту.
public struct BatteryAlerts: Equatable, Sendable {
    private struct Armed: Equatable, Sendable {
        var lowArmed: Bool
        var highArmed: Bool
        var fullArmed: Bool
    }

    private let armed: [String: Armed]

    public init() { armed = [:] }
    private init(armed: [String: Armed]) { self.armed = armed }

    public func evaluating(_ devices: [DeviceCharge]) -> (BatteryAlerts, [BatteryAlert]) {
        let low = Config.Battery.lowThreshold
        let high = Config.Battery.highThreshold
        let gap = Config.Battery.hysteresis

        var nextArmed: [String: Armed] = [:]
        var fired: [BatteryAlert] = []

        for device in devices {
            // Незнакомое устройство считается взведённым, чтобы первый же
            // замер ниже порога дал уведомление.
            var state = armed[device.name] ?? Armed(lowArmed: true, highArmed: true, fullArmed: true)

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

            let full = Config.Battery.fullThreshold
            if device.percent >= full, state.fullArmed {
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

        // Исчезнувшие устройства не переносим: при следующем подключении
        // правило должно отработать заново.
        return (BatteryAlerts(armed: nextArmed), fired)
    }
}
