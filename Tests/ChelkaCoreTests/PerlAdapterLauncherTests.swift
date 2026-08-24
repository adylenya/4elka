import Testing
import Foundation
@testable import ChelkaCore

/// Настоящий адаптер здесь не поднимается: `/usr/bin/false` вместо perl даёт
/// ровно то, что проверяется, — ненулевой код возврата.
private final class LauncherLog: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [String] = []
    func add(_ message: String) { lock.lock(); messages.append(message); lock.unlock() }
    private var all: [String] { lock.lock(); defer { lock.unlock() }; return messages }

    /// Обработчик завершения приходит на чужой очереди, поэтому ждём с опросом.
    func waitFor(_ needle: String, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if all.contains(where: { $0.contains(needle) }) { return true }
            usleep(20_000)
        }
        return false
    }
}

private func fakeAdapterOnDisk() throws -> AdapterPaths {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("chelka-adapter-\(UUID().uuidString)")
    let script = dir.appendingPathComponent("mediaremote-adapter.pl")
    let framework = dir.appendingPathComponent("MediaRemoteAdapter.framework")
    try FileManager.default.createDirectory(at: framework, withIntermediateDirectories: true)
    try Data("# заглушка: её никто не исполняет".utf8).write(to: script)
    return AdapterPaths(script: script, framework: framework)
}

private let noHandlers = AdapterStreamHandlers(output: { _ in },
                                               errorOutput: { _ in },
                                               exit: { _ in })

/// Относительный путь обязан быть отказом ДО запуска процесса: иначе perl
/// падает с «Failed to load framework», а наружу выходит одна строка про
/// «падает сразу», без пути и без причины.
@Test func launcherRefusesRelativePathsWithoutStartingAnything() {
    let launcher = PerlAdapterLauncher(
        paths: AdapterPaths(script: URL(string: "vendor/a.pl")!,
                            framework: URL(string: "vendor/f.framework")!))
    #expect(throws: AdapterLaunchError.badPaths(.relativePath("vendor/a.pl"))) {
        try launcher.launchStream(id: AdapterProcessID(raw: 0), handlers: noHandlers)
    }
}

@Test func launcherRefusesMissingAdapterWithoutStartingAnything() {
    let launcher = PerlAdapterLauncher(
        paths: AdapterPaths(script: URL(fileURLWithPath: "/tmp/нет-такого-4elka.pl"),
                            framework: URL(fileURLWithPath: "/tmp/нет-такого-4elka.framework")))
    #expect(throws: AdapterLaunchError.badPaths(.scriptMissing("/tmp/нет-такого-4elka.pl"))) {
        try launcher.launchStream(id: AdapterProcessID(raw: 0), handlers: noHandlers)
    }
}

/// Провал команды был закрыт тем же способом, что и причина смерти потока:
/// кнопка «пауза» ничего не делает, а в логе пусто.
@Test func failedCommandReportsItsExitCode() throws {
    let log = LauncherLog()
    let launcher = PerlAdapterLauncher(paths: try fakeAdapterOnDisk(),
                                       interpreter: URL(fileURLWithPath: "/usr/bin/false"),
                                       log: { log.add($0) })

    try launcher.send(.pause)

    #expect(log.waitFor("кодом 1"))
}

@Test func commandToMissingAdapterFailsLoudly() {
    let launcher = PerlAdapterLauncher(
        paths: AdapterPaths(script: URL(fileURLWithPath: "/tmp/нет-такого-4elka.pl"),
                            framework: URL(fileURLWithPath: "/tmp/нет-такого-4elka.framework")))
    #expect(throws: AdapterLaunchError.badPaths(.scriptMissing("/tmp/нет-такого-4elka.pl"))) {
        try launcher.send(.toggle)
    }
}
