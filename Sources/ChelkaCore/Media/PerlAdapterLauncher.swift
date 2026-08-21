import Foundation

/// Настоящий запуск адаптера: perl плюс скрипт рядом с фреймворком.
///
/// Обход энтайтлмента macOS 15.4+: perl уже энтайтлен, поэтому фреймворк грузит
/// он, а не мы. Всё, что связано с процессами, живёт здесь — супервизор
/// (`MediaRemoteBridge`) про `Process` не знает вовсе.
public struct PerlAdapterLauncher: AdapterLauncher {
    /// Системный perl. Параметром — только ради теста на код возврата команды:
    /// настоящего адаптера в тестах поднимать нельзя.
    public static let systemPerl = URL(fileURLWithPath: "/usr/bin/perl")

    private let paths: AdapterPaths
    private let interpreter: URL
    private let log: @Sendable (String) -> Void

    public init(paths: AdapterPaths,
                interpreter: URL = PerlAdapterLauncher.systemPerl,
                log: @escaping @Sendable (String) -> Void = { NSLog("4elka: %@", $0) }) {
        self.paths = paths
        self.interpreter = interpreter
        self.log = log
    }

    public func launchStream(id: AdapterProcessID,
                             handlers: AdapterStreamHandlers) throws -> AdapterProcess {
        if let problem = paths.problem() { throw AdapterLaunchError.badPaths(problem) }

        // Перед своим запуском убираем брошенные прошлыми запусками процессы:
        // адаптер переживает смерть хозяина и держит подписку на поток, пока
        // не попробует записать в закрытую трубу — то есть неограниченно долго.
        let orphans = AdapterOrphans.sweep(scriptPath: paths.script.path,
                                           processList: AdapterOrphans.systemProcessList,
                                           terminate: AdapterOrphans.terminatePolitely)
        if !orphans.isEmpty {
            log("погашено брошенных процессов адаптера: \(orphans.count)")
        }

        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = interpreter
        process.arguments = [paths.script.path, paths.framework.path, "stream"]
        process.standardOutput = output
        process.standardError = errors

        Self.forward(output, to: handlers.output)
        Self.forward(errors, to: handlers.errorOutput)
        process.terminationHandler = { _ in handlers.exit(id) }

        let running = PerlProcess(process: process, pipes: [output, errors])
        do {
            try process.run()
        } catch {
            // Обработчики снимаем сами: процесса нет, а трубы уже подписаны.
            running.stop()
            throw error
        }
        return running
    }

    public func send(_ command: MediaCommand) throws {
        if let problem = paths.problem() { throw AdapterLaunchError.badPaths(problem) }

        let process = Process()
        process.executableURL = interpreter
        process.arguments = [paths.script.path, paths.framework.path,
                             "send", String(command.rawValue)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        // Код возврата смотрим обязательно: без него «кнопка паузы ничего не
        // делает» не оставляет в логе ни строчки. Смотрим в обработчике
        // завершения, а не ожиданием: нажатие в интерфейсе не должно упираться
        // в чужой процесс.
        let log = self.log
        process.terminationHandler = { finished in
            guard finished.terminationStatus != 0 else { return }
            log("команда плееру \(command.rawValue) вернулась с кодом \(finished.terminationStatus)")
        }
        try process.run()
    }

    /// Куски из трубы отдаются как есть: на строки их режет тот, кто читает.
    private static func forward(_ pipe: Pipe, to sink: @escaping @Sendable (Data) -> Void) {
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            sink(chunk)
        }
    }
}

/// Процесс плюс его трубы. Держим вместе, потому что гасить их нужно вместе.
private final class PerlProcess: AdapterProcess {
    private let process: Process
    private let pipes: [Pipe]

    init(process: Process, pipes: [Pipe]) {
        self.process = process
        self.pipes = pipes
    }

    func stop() {
        for pipe in pipes { pipe.fileHandleForReading.readabilityHandler = nil }
        if process.isRunning { process.terminate() }
    }
}
