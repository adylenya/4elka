import Foundation

/// Метка запущенного процесса.
///
/// Нужна затем, что обработчик завершения приходит асинхронно и легко догоняет
/// уже запущенный СЛЕДУЮЩИЙ процесс. Очередь супервизора здесь не спасает: она
/// даёт порядок, но не тождество процесса.
public struct AdapterProcessID: Hashable, Sendable {
    public let raw: UInt64
    public init(raw: UInt64) { self.raw = raw }
}

/// Запущенный процесс адаптера — ровно то, что о нём нужно знать супервизору.
public protocol AdapterProcess: AnyObject {
    /// Гасит процесс и снимает обработчики чтения. Идемпотентно.
    ///
    /// Снять обработчик так же важно, как погасить процесс: труба умершего
    /// иначе продолжает будить нас и лить куски в общий буфер.
    func stop()
}

/// Куда процесс адаптера отдаёт то, что написал, и как сообщает о смерти.
public struct AdapterStreamHandlers: Sendable {
    /// Кусок стандартного вывода. Границы кусков со строками не совпадают.
    public let output: @Sendable (Data) -> Void
    /// Кусок потока ошибок. Именно здесь perl пишет причину, по которой умер.
    public let errorOutput: @Sendable (Data) -> Void
    /// Процесс завершился; аргумент — метка того, КТО именно завершился.
    public let exit: @Sendable (AdapterProcessID) -> Void

    public init(output: @escaping @Sendable (Data) -> Void,
                errorOutput: @escaping @Sendable (Data) -> Void,
                exit: @escaping @Sendable (AdapterProcessID) -> Void) {
        self.output = output
        self.errorOutput = errorOutput
        self.exit = exit
    }
}

/// Чем поднимают поток и чем отправляют команды.
///
/// Отдельно от супервизора намеренно: политику перезапуска, тождество процесса
/// и разбор потока иначе нельзя проверить, не поднимая настоящий адаптер — а
/// поднимать его в тестах нельзя, у хозяина машины играет музыка.
public protocol AdapterLauncher: Sendable {
    /// Поднимает долгоживущий процесс чтения потока. `id` вернётся в
    /// `handlers.exit`, когда этот процесс умрёт.
    func launchStream(id: AdapterProcessID, handlers: AdapterStreamHandlers) throws -> AdapterProcess
    /// Короткий вызов на одну команду плееру.
    func send(_ command: MediaCommand) throws
}

/// Отказ запуска, о котором есть что сказать человеку.
public enum AdapterLaunchError: Error, Equatable {
    case badPaths(AdapterPathProblem)

    public var message: String {
        switch self {
        case .badPaths(let problem): return problem.message
        }
    }
}
