import Testing
import Foundation
@testable import ChelkaCore

/// Настоящий адаптер в тестах не поднимается ни разу: у хозяина машины играет
/// музыка, и лишние процессы адаптера ему не нужны. Вместо процессов —
/// подставной запускатель, которым тест дёргает те же обработчики.

private enum FakeLaunchError: Error { case refused }

private final class FakeProcess: AdapterProcess, @unchecked Sendable {
    private let lock = NSLock()
    private var _stops = 0
    var stops: Int { lock.lock(); defer { lock.unlock() }; return _stops }
    func stop() { lock.lock(); _stops += 1; lock.unlock() }
}

private struct Launch {
    let id: AdapterProcessID
    let handlers: AdapterStreamHandlers
    let process: FakeProcess
}

private final class FakeLauncher: AdapterLauncher, @unchecked Sendable {
    private let lock = NSLock()
    private var _launches: [Launch] = []
    private var _attempts = 0
    private var _failures = 0
    private var _sent: [MediaCommand] = []
    /// Каждая попытка запуска — сигнал: тест синхронный, мост живёт на очереди.
    private let attempted = DispatchSemaphore(value: 0)

    init(failFirstLaunches: Int = 0) { _failures = failFirstLaunches }

    func launchStream(id: AdapterProcessID,
                      handlers: AdapterStreamHandlers) throws -> AdapterProcess {
        lock.lock()
        _attempts += 1
        let shouldFail = _failures > 0
        if shouldFail { _failures -= 1 }
        let process = FakeProcess()
        if !shouldFail { _launches.append(Launch(id: id, handlers: handlers, process: process)) }
        lock.unlock()
        attempted.signal()
        if shouldFail { throw FakeLaunchError.refused }
        return process
    }

    func send(_ command: MediaCommand) throws {
        lock.lock(); _sent.append(command); lock.unlock()
    }

    var attempts: Int { lock.lock(); defer { lock.unlock() }; return _attempts }
    var launches: [Launch] { lock.lock(); defer { lock.unlock() }; return _launches }
    var last: Launch? { launches.last }
    var sent: [MediaCommand] { lock.lock(); defer { lock.unlock() }; return _sent }

    @discardableResult
    func waitForAttempt(timeout: TimeInterval = 2) -> Bool {
        attempted.wait(timeout: .now() + timeout) == .success
    }
}

/// Собирает то, что мост сказал в лог, из любой очереди.
private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _messages: [String] = []
    func add(_ message: String) { lock.lock(); _messages.append(message); lock.unlock() }
    var messages: [String] { lock.lock(); defer { lock.unlock() }; return _messages }
    func sawMessage(containing needle: String) -> Bool {
        messages.contains { $0.contains(needle) }
    }
}

/// Мост отдаёт состояние через главную очередь, поэтому тесту надо ей уступить.
private func settle() async {
    try? await Task.sleep(for: .milliseconds(60))
}

@MainActor
private func bridge(_ launcher: FakeLauncher,
                    log: Recorder = Recorder()) -> MediaRemoteBridge {
    MediaRemoteBridge(launcher: launcher, scheduler: .immediate, log: { log.add($0) })
}

// MARK: - Тождество процесса

/// `stop()` гасит процесс, сигнал доходит асинхронно, и обработчик завершения
/// уже мёртвого p1 приезжает, когда работает запущенный заново p2. Раньше он
/// убивал живого p2 и засчитывал это мгновенным отказом.
@Test @MainActor func exitHandlerOfDeadProcessDoesNotKillTheLiveOne() {
    let launcher = FakeLauncher()
    let b = bridge(launcher)
    b.start(onState: { _ in }, onUnavailable: {})
    #expect(launcher.waitForAttempt())
    let first = try! #require(launcher.last)

    b.stop()
    b.start(onState: { _ in }, onUnavailable: {})
    #expect(launcher.waitForAttempt())
    let second = try! #require(launcher.last)
    #expect(second.id != first.id)

    // Обработчик мёртвого p1 приезжает при живом p2.
    first.handlers.exit(first.id)
    b.waitForPendingWork()

    #expect(second.process.stops == 0)
    // И перезапуска он тоже не заказывает: живой процесс уже есть.
    #expect(launcher.attempts == 2)
}

/// Куски из трубы мёртвого процесса не должны попадать в разбор живого.
@Test @MainActor func outputOfDeadProcessIsIgnored() async {
    let launcher = FakeLauncher()
    let b = bridge(launcher)
    var titles: [String?] = []
    b.start(onState: { titles.append($0.title) }, onUnavailable: {})
    #expect(launcher.waitForAttempt())
    let first = try! #require(launcher.last)

    b.stop()
    b.start(onState: { titles.append($0.title) }, onUnavailable: {})
    #expect(launcher.waitForAttempt())

    first.handlers.output(Data((#"{"diff":false,"payload":{"title":"Призрак"}}"# + "\n").utf8))
    b.waitForPendingWork()
    await settle()

    #expect(titles.isEmpty)
}

// MARK: - Перезапуск начинает разбор с чистого листа

/// Процесс умер посреди строки, в буфере остался огрызок. Первая строка нового
/// процесса — ПОЛНЫЙ снимок состояния, единственный за сеанс. Приклеенный
/// огрызок делал её неразбираемой, и дальше все диффы ложились на СТАРОЕ
/// состояние: панель уверенно показывала прошлый трек сколько угодно долго.
@Test @MainActor func firstSnapshotOfNewProcessIsNotGluedToLeftoversOfTheDeadOne() async {
    let launcher = FakeLauncher()
    let b = bridge(launcher)
    var titles: [String?] = []
    b.start(onState: { titles.append($0.title) }, onUnavailable: {})
    #expect(launcher.waitForAttempt())
    let first = try! #require(launcher.last)

    first.handlers.output(Data((#"{"diff":false,"payload":{"title":"Старый","artist":"А"}}"# +
                                "\n" + #"{"diff":false,"payl"#).utf8))
    first.handlers.exit(first.id)
    #expect(launcher.waitForAttempt())
    let second = try! #require(launcher.last)

    second.handlers.output(Data((#"{"diff":false,"payload":{"title":"Новый","artist":"Б"}}"# + "\n").utf8))
    b.waitForPendingWork()
    await settle()

    #expect(titles.last == "Новый")
}

/// Свой собственный обработчик мост обязан обработать: процесс умер — перезапуск.
@Test @MainActor func exitOfCurrentProcessLeadsToRestart() {
    let launcher = FakeLauncher()
    let b = bridge(launcher)
    b.start(onState: { _ in }, onUnavailable: {})
    #expect(launcher.waitForAttempt())
    let first = try! #require(launcher.last)

    first.handlers.exit(first.id)

    #expect(launcher.waitForAttempt())
    #expect(launcher.attempts == 2)
    #expect(first.process.stops == 1)
}
