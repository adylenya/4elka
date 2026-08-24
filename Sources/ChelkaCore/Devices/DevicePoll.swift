import Foundation

/// Итог одного опроса устройств.
///
/// Пустой список и сорвавшийся опрос — разные события, и различать их
/// обязательно. `SystemCommandRunner.run` отдаёт `nil` и когда устройство
/// отключили, и когда утилита не отработала: ненулевой код возврата, вышел
/// срок, нет самой утилиты. По второму забывать взведение нельзя — иначе
/// правило порога отработает заново, и карточка выедет второй раз на том же
/// заряде.
public struct DevicePoll: Equatable, Sendable {
    public let devices: [DeviceCharge]
    /// Источники, которые в этом опросе ответили. Устройство забывается только
    /// когда его источник ответил, а устройства в ответе не оказалось.
    public let answered: Set<DeviceCharge.Source>

    public init(devices: [DeviceCharge], answered: Set<DeviceCharge.Source>) {
        self.devices = devices
        self.answered = answered
    }

    /// Опрос, в котором ответили все источники.
    public static func complete(_ devices: [DeviceCharge]) -> DevicePoll {
        DevicePoll(devices: devices, answered: Set(DeviceCharge.Source.allCases))
    }

    /// Опрос, в котором не ответил никто: все три утилиты сорвались.
    public static let failed = DevicePoll(devices: [], answered: [])
}
