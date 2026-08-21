import Foundation

/// Чем откладывается повторная попытка запуска.
public enum RestartScheduler: Sendable {
    /// Настоящая пауза, растущая по политике перезапуска.
    case realTime
    /// Без паузы. Только для тестов: иначе проверка «сдаюсь после исчерпания
    /// попыток» ждала бы настоящие 1 + 2 + 4 + 8 + 16 секунд.
    case immediate
}

/// Супервизор потока плеера: поднимает долгоживущий процесс адаптера, читает из
/// него состояние и перезапускает по политике, когда он умирает.
///
/// Про `Process` этот класс не знает ничего — запуск отдан `AdapterLauncher`.
/// Так политику перезапуска, тождество процесса и разбор потока можно проверить
/// тестом, не поднимая настоящий адаптер.
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

    private let launcher: AdapterLauncher
    private let scheduler: RestartScheduler
    private let log: @Sendable (String) -> Void

    /// Всё изменяемое состояние живёт на одной последовательной очереди.
    /// Обработчик завершения процесса Foundation вызывает на произвольной очереди,
    /// поэтому «честное слово» о потокобезопасности здесь не работает: без этой
    /// очереди чтение флага остановки было бы настоящей гонкой.
    private let supervision = DispatchQueue(label: "chelka.media.supervision")
    private var process: AdapterProcess?
    private var currentID: AdapterProcessID?
    private var nextID: UInt64 = 0
    private var startedAt: Date?
    private var state = NowPlaying.empty
    private var buffer = LineBuffer()
    private var policy = RestartPolicy.initial
    private var stopped = false

    public convenience init(paths: AdapterPaths) {
        self.init(launcher: PerlAdapterLauncher(paths: paths))
    }

    public init(launcher: AdapterLauncher,
                scheduler: RestartScheduler = .realTime,
                log: @escaping @Sendable (String) -> Void = { NSLog("4elka: %@", $0) }) {
        self.launcher = launcher
        self.scheduler = scheduler
        self.log = log
    }

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

    public func send(_ command: MediaCommand) {
        supervision.async { [self] in
            do {
                try launcher.send(command)
            } catch {
                log("команда плееру \(command.rawValue) не ушла: \(Self.describe(error))")
            }
        }
    }

    /// Ждёт, пока очередь супервизора доработает уже поставленные задачи.
    /// Нужна тесту: он синхронный, а мост живёт на своей очереди.
    func waitForPendingWork() {
        supervision.sync {}
    }

    /// Гасит процесс и снимает обработчик чтения. Идемпотентно.
    /// Вызывается только на очереди супервизора.
    private func teardownLocked() {
        process?.stop()
        process = nil
        currentID = nil
        startedAt = nil
    }

    /// Вызывается только на очереди супервизора.
    private func launchLocked() {
        // Без этой проверки повторный `start()` или перезапуск, обогнавший его,
        // оставили бы два живых процесса: старый осиротел бы вместе со своим
        // обработчиком чтения, и оба писали бы в один буфер.
        guard process == nil, !stopped else { return }

        let id = AdapterProcessID(raw: nextID)
        nextID += 1
        do {
            process = try launcher.launchStream(id: id, handlers: handlers(for: id))
            currentID = id
            startedAt = Date()
        } catch {
            log("поток плеера не запустился: \(Self.describe(error))")
            reportUnavailable()
        }
    }

    private func handlers(for id: AdapterProcessID) -> AdapterStreamHandlers {
        AdapterStreamHandlers(
            output: { [weak self] chunk in
                guard let self else { return }
                supervision.async { self.consumeLocked(chunk, from: id) }
            },
            errorOutput: { _ in },
            exit: { [weak self] finished in
                guard let self else { return }
                supervision.async { self.handleExitLocked(finished) }
            })
    }

    /// Вызывается только на очереди супервизора.
    private func handleExitLocked(_ finished: AdapterProcessID) {
        // Обработчик ЧУЖОГО процесса игнорируется целиком: ни teardown, ни
        // счётчик отказов. `stop()` гасит процесс, сигнал доходит асинхронно —
        // и обработчик уже мёртвого p1 приезжает, когда работает поднятый
        // заново p2. Раньше он убивал живого p2, засчитывал это мгновенным
        // отказом и растил задержку, хотя адаптер был полностью здоров.
        // Очередь супервизора тут не помогает: она даёт порядок, но не
        // тождество процесса.
        guard finished == currentID else {
            log("завершение пришло от прошлого процесса адаптера, игнорирую")
            return
        }
        let lifetime = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        teardownLocked()
        // Проверка стоит ЗДЕСЬ, а не только перед постановкой задержки: раньше
        // отложенный перезапуск успевал сработать уже после остановки и поднимал
        // новый процесс, то есть `stop()` ничего не останавливал.
        guard !stopped else { return }

        policy = policy.afterExit(livedFor: lifetime)
        guard !policy.shouldGiveUp else {
            log("поток плеера падает сразу при запуске, прекращаю попытки")
            reportUnavailable()
            return
        }
        scheduleLaunchLocked(after: policy.delay)
    }

    /// Вызывается только на очереди супервизора.
    ///
    /// Захват слабый намеренно: сильный держал бы мост живым всю паузу и мог бы
    /// поднять процесс уже никому не нужному моста-сироте.
    private func scheduleLaunchLocked(after delay: TimeInterval) {
        switch scheduler {
        case .realTime:
            supervision.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.launchLocked()
            }
        case .immediate:
            supervision.async { [weak self] in self?.launchLocked() }
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
    private func consumeLocked(_ chunk: Data, from id: AdapterProcessID) {
        // Кусок из трубы прошлого процесса — тот же случай, что и чужое
        // завершение: он уже был поставлен в очередь, когда процесс умер.
        // В буфер живого его пускать нельзя, там он склеится с чужой строкой.
        guard id == currentID else { return }
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

    private static func describe(_ error: Error) -> String {
        (error as? AdapterLaunchError)?.message ?? String(describing: error)
    }
}

/// Само соответствие протоколу. Методы объявлены выше в теле класса и
/// неизолированы: неизолированный код можно звать откуда угодно, в том числе с
/// главного актора, поэтому требование, изолированное на него, он выполняет.
extension MediaRemoteBridge: MediaSource {}
