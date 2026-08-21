import Foundation

public protocol CommandRunning: Sendable {
    func run(_ path: String, _ args: [String]) -> String?
}

public struct SystemCommandRunner: CommandRunning {
    public init() {}

    public func run(_ path: String, _ args: [String]) -> String? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Айфон отдаёт заряд только по кабелю: по блютусу он его не рапортует,
/// а из iCloud наружу не отдают. Утилиты нет — строка просто не показывается.
public enum PhoneBattery {
    static let toolPath = "/opt/homebrew/bin/ideviceinfo"

    public static func isAvailable(runner: CommandRunning) -> Bool {
        read(runner: runner) != nil
    }

    public static func read(runner: CommandRunning) -> DeviceCharge? {
        guard let raw = runner.run(toolPath,
                                  ["-q", "com.apple.mobile.battery", "-k", "BatteryCurrentCapacity"]),
              let percent = Int(raw), (0...100).contains(percent) else { return nil }
        let charging = runner.run(toolPath,
                                 ["-q", "com.apple.mobile.battery", "-k", "BatteryIsCharging"]) == "true"
        let name = runner.run(toolPath, ["-k", "DeviceName"]) ?? "Айфон"
        return DeviceCharge(name: name, percent: percent, isCharging: charging,
                            source: .phone, symbol: "iphone")
    }
}
