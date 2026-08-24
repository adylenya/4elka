import Foundation

/// Итог разбора вывода `system_profiler`: не только устройства, но и сколько
/// подключённых нашлось.
///
/// Различать это обязательно. «Блютус пуст» и «устройства подключены, а формат
/// вывода поменялся» — разные события: во втором случае из списка молча
/// исчезали ВСЕ устройства, и в логе не оставалось ни следа.
public struct BluetoothReading: Equatable, Sendable {
    public let devices: [DeviceCharge]
    public let connectedCount: Int

    /// Подключённые устройства есть, а ни одного уровня заряда разобрать
    /// не удалось. Либо ни у одного его нет (колонка, старая мышь), либо
    /// поменялся формат — в обоих случаях об этом стоит сказать в лог.
    public var isUnreadable: Bool { connectedCount > 0 && devices.isEmpty }
}

/// Структура вывода `system_profiler SPBluetoothDataType -json` снята с живой машины:
/// `SPBluetoothDataType[0].device_connected` — массив словарей с единственным
/// ключом-именем устройства, внутри `device_batteryLevelLeft` / `device_batteryLevelRight` /
/// `device_batteryLevelMain`. На целевой машине уровни ушей приходят строками
/// вида `"100%"`, а `device_batteryLevelMain` отсутствует вовсе; на других
/// версиях macOS тот же уровень приходит числом `51`.
public enum BluetoothParser {
    public static func parse(_ data: Data) -> [DeviceCharge] {
        let reading = reading(data)
        if reading.isUnreadable {
            NSLog("4elka: блютус-устройств подключено %d, а уровень заряда не разобрался ни у одного — проверьте формат вывода system_profiler",
                  reading.connectedCount)
        }
        return reading.devices
    }

    static func reading(_ data: Data) -> BluetoothReading {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]] else {
            return BluetoothReading(devices: [], connectedCount: 0)
        }

        var result: [DeviceCharge] = []
        var connected = 0
        for section in sections {
            guard let entries = section["device_connected"] as? [[String: Any]] else { continue }
            for entry in entries {
                for (name, raw) in entry {
                    connected += 1
                    guard let info = raw as? [String: Any],
                          let percent = percentage(from: info) else { continue }
                    result.append(DeviceCharge(name: name, percent: percent, isCharging: false,
                                               source: .bluetooth,
                                               symbol: symbol(for: info["device_minorType"] as? String)))
                }
            }
        }
        return BluetoothReading(devices: result, connectedCount: connected)
    }

    /// У наушников два уха: берём меньшее, иначе показанная цифра врала бы в плюс.
    private static func percentage(from info: [String: Any]) -> Int? {
        Config.Devices.bluetoothLevelKeys.compactMap { percent(from: info[$0]) }.min()
    }

    /// Уровень приходит то строкой `"51%"`, то числом `51` — как повезёт
    /// с версией macOS. Всё, что вне 0…100, — не заряд: `"-5%"` иначе проходил
    /// как −5 и тут же давал «заряд на исходе», а `"900%"` — «заряжен».
    static func percent(from raw: Any?) -> Int? {
        let value: Int?
        switch raw {
        case let text as String:
            value = Int(text.replacingOccurrences(of: "%", with: "")
                .trimmingCharacters(in: .whitespaces))
        case let number as Int:
            value = number
        case let number as Double:
            value = Int(number.rounded())
        default:
            value = nil
        }
        guard let value, Config.Devices.percentRange.contains(value) else { return nil }
        return value
    }

    private static func symbol(for minorType: String?) -> String {
        switch minorType {
        case "Headphones": return "airpods"
        case "Mouse": return "magicmouse"
        case "Keyboard": return "keyboard"
        default: return "dot.radiowaves.left.and.right"
        }
    }
}
