import Foundation

public protocol CommandRunning: Sendable {
    func run(_ path: String, _ args: [String]) -> String?
    /// Есть ли утилита вообще. Отдельно от `run`, потому что ответ «да/нет»
    /// не должен запускать процессы: `PhoneBattery.isAvailable` из-за этого
    /// запускал до трёх.
    func isExecutable(_ path: String) -> Bool
}

extension CommandRunning {
    public func isExecutable(_ path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }
}

public struct SystemCommandRunner: CommandRunning {
    /// Сколько ждать утилиту, прежде чем считать её повисшей и убить.
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = Config.Devices.commandTimeout) {
        self.timeout = timeout
    }

    public func run(_ path: String, _ args: [String]) -> String? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }

        // Срок обязателен. `ideviceinfo` на заблокированном айфоне, который
        // не доверяет машине, висит на usbmuxd НАВСЕГДА, а чтение до конца
        // трубы ждёт его столько же — поток занимался намертво, и таймер
        // добавлял по такому потоку в минуту.
        //
        // Сторож убивает процесс, а не прерывает чтение: убитый ребёнок
        // закрывает свой конец трубы, и чтение возвращается само. В сторож
        // уезжает только pid — число, а не сам `Process`, который делить
        // между потоками нельзя.
        let pid = process.processIdentifier
        let watchdog = DispatchWorkItem {
            NSLog("4elka: утилита %@ не ответила за отведённый срок, снимаю", path)
            kill(pid, SIGKILL)
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout,
                                                      execute: watchdog)

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        // Отменять надо до `waitUntilExit`: пока процесс не пожали, его pid
        // занят зомби и никому другому достаться не может.
        watchdog.cancel()
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
        // Пустая строка — это отсутствие имени, а не имя. Имя айфона служит и
        // опознавателем устройства, и ключом памяти порогов заряда: устройство
        // с пустым именем ломало бы и список, и гистерезис.
        let reported = runner.run(toolPath, ["-k", "DeviceName"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (reported?.isEmpty == false ? reported : nil) ?? Config.Devices.phoneFallbackName
        return DeviceCharge(name: name, percent: percent, isCharging: charging,
                            source: .phone, symbol: "iphone")
    }
}
