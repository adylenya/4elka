import Foundation

public enum MacBatteryParser {
    public static func parse(_ output: String) -> DeviceCharge? {
        for line in output.split(separator: "\n") {
            guard line.contains("InternalBattery") else { continue }
            guard let range = line.range(of: #"\d+(?=%)"#, options: .regularExpression),
                  let percent = Int(line[range]) else { continue }
            let charging = line.contains("charging") && !line.contains("discharging")
            return DeviceCharge(name: "Мак", percent: percent,
                                isCharging: charging || line.contains("charged"),
                                source: .mac, symbol: "laptopcomputer")
        }
        return nil
    }
}
