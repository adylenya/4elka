import Foundation

/// Структура вывода `system_profiler SPBluetoothDataType -json` снята с живой машины:
/// `SPBluetoothDataType[0].device_connected` — массив словарей с единственным
/// ключом-именем устройства, внутри `device_batteryLevelLeft` / `device_batteryLevelRight` /
/// `device_batteryLevelMain` строками вида `"51%"`.
public enum BluetoothParser {
    public static func parse(_ data: Data) -> [DeviceCharge] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]] else { return [] }

        var result: [DeviceCharge] = []
        for section in sections {
            guard let connected = section["device_connected"] as? [[String: Any]] else { continue }
            for entry in connected {
                for (name, raw) in entry {
                    guard let info = raw as? [String: Any],
                          let percent = percentage(from: info) else { continue }
                    result.append(DeviceCharge(name: name, percent: percent, isCharging: false,
                                               source: .bluetooth,
                                               symbol: symbol(for: info["device_minorType"] as? String)))
                }
            }
        }
        return result
    }

    /// У наушников два уха: берём меньшее, иначе показанная цифра врала бы в плюс.
    private static func percentage(from info: [String: Any]) -> Int? {
        let levels = ["device_batteryLevelLeft", "device_batteryLevelRight", "device_batteryLevelMain"]
            .compactMap { info[$0] as? String }
            .compactMap { Int($0.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) }
        return levels.min()
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
