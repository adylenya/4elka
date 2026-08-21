import Darwin
import Foundation

/// Уборка осиротевших процессов адаптера.
///
/// Замерено 21.08 на живой машине: процесс адаптера **переживает смерть
/// хозяина**. Труба к нему закрывается, но сам он умирает лишь при следующей
/// попытке записи, а пишет он только когда меняется состояние плеера. Значит
/// после прибитого или упавшего приложения процесс висит в системе сколько
/// угодно долго, держа подписку на поток. Накопить их можно сколько раз
/// приложение прибили.
///
/// Гасим только своё и только брошенное: командная строка обязана начинаться с
/// того же `perl` и содержать наш путь к скрипту, а родителем должен быть
/// первый процесс системы. Живого ребёнка другого запущенного экземпляра это
/// правило не трогает — у него родитель тот экземпляр, а не система.
public enum AdapterOrphans {
    /// Разбирает вывод `ps -eo pid=,ppid=,command=`. Чистая функция: проверяется
    /// тестом на подделанном выводе, а не запуском процессов.
    public static func pids(inProcessList list: String, scriptPath: String) -> [Int32] {
        list.split(separator: "\n").compactMap { line -> Int32? in
            guard let row = Self.row(in: line), row.parent == Self.initProcess else { return nil }
            // Проверка на `perl` обязательна: путь к скрипту встречается и в
            // командных строках компилятора, и по такому шаблону уже один раз
            // убили чужую сборку.
            guard row.command.hasPrefix("\(Self.perlPath) "),
                  row.command.contains(scriptPath) else { return nil }
            return row.pid
        }
    }

    /// Разбирает одну строку `ps` на два числа и командную строку.
    ///
    /// Командная строка берётся ОДНИМ куском по смещению в исходной строке, а
    /// не пересклейкой полей через пробел: склейка схлопывает повторяющиеся
    /// пробелы, и корень проекта с двойным пробелом в имени каталога перестаёт
    /// совпадать — брошенные процессы не находятся вовсе.
    private static func row(in line: Substring) -> (pid: Int32, parent: Int32, command: Substring)? {
        let afterPid = line.drop(while: { $0 == " " })
        guard let pidEnd = afterPid.firstIndex(of: " ") else { return nil }
        let parentField = afterPid[pidEnd...].drop(while: { $0 == " " })
        guard let parentEnd = parentField.firstIndex(of: " ") else { return nil }
        let command = parentField[parentEnd...].drop(while: { $0 == " " })
        guard let pid = Int32(afterPid[afterPid.startIndex..<pidEnd]),
              let parent = Int32(parentField[parentField.startIndex..<parentEnd]),
              !command.isEmpty else { return nil }
        return (pid, parent, command)
    }

    /// Находит брошенные процессы и гасит их. Возвращает то, что погасило.
    /// Список процессов и способ гасить приходят снаружи, чтобы тест обошёлся
    /// без настоящих процессов.
    public static func sweep(scriptPath: String,
                            processList: () -> String?,
                            terminate: (Int32) -> Void) -> [Int32] {
        guard let list = processList() else { return [] }
        let found = pids(inProcessList: list, scriptPath: scriptPath)
        for pid in found { terminate(pid) }
        return found
    }

    /// Настоящий список процессов системы.
    public static func systemProcessList() -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-eo", "pid=,ppid=,command="]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    /// Вежливое завершение: адаптеру нечего сохранять, но `SIGKILL` не оставил
    /// бы ему шанса убрать за собой подписку на поток.
    public static func terminatePolitely(_ pid: Int32) {
        _ = kill(pid, SIGTERM)
    }

    private static let initProcess: Int32 = 1
    private static let perlPath = "/usr/bin/perl"
}
