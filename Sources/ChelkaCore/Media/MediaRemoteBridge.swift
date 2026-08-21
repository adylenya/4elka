import Foundation

public struct AdapterPaths {
    public let script: URL
    public let framework: URL

    public init(script: URL, framework: URL) {
        self.script = script
        self.framework = framework
    }

    public static func bundled(in bundle: Bundle) -> AdapterPaths? {
        guard let resources = bundle.resourceURL else { return nil }
        let script = resources.appendingPathComponent("mediaremote-adapter.pl")
        let framework = resources.appendingPathComponent("MediaRemoteAdapter.framework")
        guard FileManager.default.fileExists(atPath: script.path) else { return nil }
        return AdapterPaths(script: script, framework: framework)
    }

    public static func developmentTree(projectRoot: URL) -> AdapterPaths {
        AdapterPaths(
            script: projectRoot.appendingPathComponent("vendor/mediaremote-adapter/bin/mediaremote-adapter.pl"),
            framework: projectRoot.appendingPathComponent("vendor/build/MediaRemoteAdapter.framework"))
    }
}

/// Один долгоживущий процесс на чтение потока плюс короткие вызовы на команды.
/// Обход энтайтлмента macOS 15.4+: perl уже энтайтлен, поэтому фреймворк грузит он.
///
/// Соответствие `MediaSource` объявлено расширением ниже, а не здесь: в
/// основном объявлении класса оно затянуло бы на главный актор ВСЁ содержимое,
/// включая состояние, которое живёт на очереди супервизора.
public final class MediaRemoteBridge: @unchecked Sendable {
    /// Обработчики приходят в `start` и дальше только читаются. Снаружи их
    /// поставить нельзя — иначе неизолированный источник опять разрешал бы
    /// запись из любого потока.
    private var onState: (@MainActor (NowPlaying) -> Void)?
    private var onUnavailable: (@MainActor () -> Void)?

    private let paths: AdapterPaths
    /// Всё изменяемое состояние живёт на одной последовательной очереди.
    /// Обработчик завершения процесса Foundation вызывает на произвольной очереди,
    /// поэтому «честное слово» о потокобезопасности здесь не работает: без этой
    /// очереди чтение флага остановки было бы настоящей гонкой.
    private let supervision = DispatchQueue(label: "chelka.media.supervision")
    private var process: Process?
    private var pipe: Pipe?
    private var startedAt: Date?
    private var state = NowPlaying.empty
    private var buffer = LineBuffer()
    private var policy = RestartPolicy.initial
    private var stopped = false

    public init(paths: AdapterPaths) { self.paths = paths }

    public func start(onState: @escaping @MainActor (NowPlaying) -> Void,
                      onUnavailable: @escaping @MainActor () -> Void) {
        supervision.async { [self] in
            self.onState = onState
            self.onUnavailable = onUnavailable
            stopped = false
            policy = .initial
            launchLocked()
        }
    }

    public func stop() {
        supervision.async { [self] in
            stopped = true
            teardownLocked()
        }
    }

    /// Снимает обработчик чтения и гасит процесс. Идемпотентно.
    private func teardownLocked() {
        pipe?.fileHandleForReading.readabilityHandler = nil
        pipe = nil
        if let running = process, running.isRunning { running.terminate() }
        process = nil
        startedAt = nil
    }

    public func send(_ command: MediaCommand) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [paths.script.path, paths.framework.path, "send", String(command.rawValue)]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
        } catch {
            NSLog("4elka: команда плееру %d не ушла: %@",
                  command.rawValue, String(describing: error))
        }
    }

    /// Вызывается только на очереди супервизора.
    private func launchLocked() {
        // Без этой проверки повторный `start()` или перезапуск, обогнавший его,
        // оставили бы два живых процесса: старый осиротел бы вместе со своим
        // обработчиком чтения, и оба писали бы в один буфер.
        guard process == nil, !stopped else { return }

        // Отсутствующий адаптер даёт коварный случай: сам perl на месте, запуск
        // «удаётся», а процесс умирает мгновенно. Без этой проверки приложение
        // молча дёргало бы его вечно, ни разу не сказав, что плеера нет.
        let fm = FileManager.default
        guard fm.fileExists(atPath: paths.script.path),
              fm.fileExists(atPath: paths.framework.path) else {
            NSLog("4elka: адаптер плеера не найден по пути %@", paths.script.path)
            reportUnavailable()
            return
        }

        // Перед своим запуском убираем брошенные прошлыми запусками процессы:
        // адаптер переживает смерть хозяина и держит подписку на поток, пока
        // не попробует записать в закрытую трубу — то есть неограниченно долго.
        let orphans = AdapterOrphans.sweep(scriptPath: paths.script.path,
                                           processList: AdapterOrphans.systemProcessList,
                                           terminate: AdapterOrphans.terminatePolitely)
        if !orphans.isEmpty {
            NSLog("4elka: погашено брошенных процессов адаптера: %d", orphans.count)
        }

        let p = Process()
        let outputPipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [paths.script.path, paths.framework.path, "stream"]
        p.standardOutput = outputPipe
        p.standardError = FileHandle.nullDevice

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty, let self else { return }
            self.supervision.async { self.consumeLocked(chunk) }
        }

        p.terminationHandler = { [weak self] _ in
            guard let self else { return }
            self.supervision.async { self.handleExitLocked() }
        }

        do {
            try p.run()
            process = p
            pipe = outputPipe
            startedAt = Date()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            NSLog("4elka: не удалось запустить поток плеера: %@", String(describing: error))
            reportUnavailable()
        }
    }

    /// Вызывается только на очереди супервизора.
    private func handleExitLocked() {
        let lifetime = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        teardownLocked()
        // Проверка стоит ЗДЕСЬ, а не только перед постановкой задержки: раньше
        // отложенный перезапуск успевал сработать уже после остановки и поднимал
        // новый процесс, то есть `stop()` ничего не останавливал.
        guard !stopped else { return }

        policy = policy.afterExit(livedFor: lifetime)
        guard !policy.shouldGiveUp else {
            NSLog("4elka: поток плеера падает сразу при запуске, прекращаю попытки")
            reportUnavailable()
            return
        }
        supervision.asyncAfter(deadline: .now() + policy.delay) { [self] in
            launchLocked()
        }
    }

    /// Обработчики изолированы на главный актор, поэтому и зовём их только
    /// оттуда: очередь главного потока — это он и есть.
    private func reportUnavailable() {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.onUnavailable?() }
        }
    }

    /// Вызывается только на очереди супервизора.
    private func consumeLocked(_ chunk: Data) {
        let lines = buffer.appending(chunk)
        guard !lines.isEmpty else { return }
        for line in lines {
            guard let parsed = NowPlayingLine.parse(line) else { continue }
            state = state.applying(parsed)
        }
        let snapshot = state
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.onState?(snapshot) }
        }
    }
}

/// Само соответствие протоколу. Методы объявлены выше в теле класса и
/// неизолированы: неизолированный код можно звать откуда угодно, в том числе с
/// главного актора, поэтому требование, изолированное на него, он выполняет.
extension MediaRemoteBridge: MediaSource {}
