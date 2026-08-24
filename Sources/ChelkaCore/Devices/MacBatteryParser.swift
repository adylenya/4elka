import Foundation

public enum MacBatteryParser {
    /// Состояние батареи, как его печатает pmset. Перечислено явно и полностью:
    /// поиск подстроки по всей строке читал `not charging` как «на зарядке»
    /// (слово `charging` внутри есть, `discharging` — нет), и на 80% под
    /// оптимизированной зарядкой выезжала карточка «можно отключать», когда
    /// система сама остановила ток и отключать было нечего.
    enum State: Equatable, Sendable {
        case charging
        case discharging
        case charged
        case notCharging
        case finishingCharge
        /// Кабель есть, а про ток ничего не сказано.
        case acAttached

        /// Слова, которыми pmset называет состояние. Длинные раньше коротких:
        /// поле сверяется по началу, и `not charging` не должно совпасть
        /// с `charging`.
        static let byPhrase: [(String, State)] = [
            ("not charging", .notCharging),
            ("finishing charge", .finishingCharge),
            ("discharging", .discharging),
            ("charging", .charging),
            ("charged", .charged),
            ("AC attached", .acAttached),
        ]

        /// Идёт ли ток в батарею. `AC attached` сам по себе — нет: обещать
        /// «можно отключать» на нём нельзя.
        var isCharging: Bool {
            switch self {
            case .charging, .charged, .finishingCharge: return true
            case .discharging, .notCharging, .acAttached: return false
            }
        }
    }

    public static func parse(_ output: String) -> DeviceCharge? {
        for line in output.split(separator: "\n") {
            guard line.contains("InternalBattery") else { continue }
            guard let range = line.range(of: #"\d+(?=%)"#, options: .regularExpression),
                  let percent = Int(line[range]) else { continue }
            return DeviceCharge(name: "Мак", percent: percent,
                               isCharging: state(of: line)?.isCharging ?? false,
                               source: .mac, symbol: "laptopcomputer")
        }
        return nil
    }

    /// Состояние ищется по полю между `;`, а не подстрокой по всей строке.
    /// Поля идут в произвольном составе: `86%; charging; (no estimate) present: true`,
    /// `80%; AC attached; not charging present: true` — поэтому проверяется каждое,
    /// а хвост поля (`present: true`, остаток времени) отбрасывается сверкой
    /// по началу. Побеждает самое определённое: `AC attached` рядом с `charging`
    /// не должен перебить зарядку.
    static func state(of line: some StringProtocol) -> State? {
        var found: State?
        for field in line.split(separator: ";") {
            let trimmed = field.trimmingCharacters(in: .whitespaces)
            guard let match = State.byPhrase.first(where: { trimmed.hasPrefix($0.0) })?.1
            else { continue }
            if match == .acAttached, found != nil { continue }
            if found == nil || found == .acAttached { found = match }
        }
        return found
    }
}
