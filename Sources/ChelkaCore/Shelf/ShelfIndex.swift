import Foundation

/// Полка на диске. Пишется атомарно, читается терпимо: обрыв записи не должен
/// оставить половину файла, а битый файл — уронить приложение или молча стереть
/// полку.
public struct ShelfIndex: Sendable {
    private let file: StateFile

    public init(fileURL: URL) {
        self.file = StateFile(fileURL: fileURL, subject: "полка")
    }

    public func save(_ store: ShelfStore) throws {
        try file.write(store.items)
    }

    /// Настоящая проверка файловой системы. Зовётся вне главной очереди —
    /// см. `ShelfCoordinator.load`.
    public func load() -> ShelfStore {
        load(reachability: FileReachabilityProbe.onDisk)
    }

    /// Пустая полка — это только отсутствие файла. Битый файл откладывается
    /// в сторону, а не подменяется пустотой: иначе первая же запись затрёт его,
    /// и файлы, положенные руками, исчезнут навсегда. Почему именно так —
    /// в `StateFile`.
    ///
    /// Записи с пропавшими файлами отбрасываются: полка самолечится, как и
    /// история. Записи на недостижимом томе остаются с пометкой — см.
    /// `ShelfStore.prunedOfMissingFiles`.
    ///
    /// Проверка достижимости вынесена в параметр ради тестов: они не должны
    /// зависеть ни от того, что лежит на настоящем диске, ни от того, что
    /// на машине смонтировано.
    public func load(reachability: (URL) -> FileReachability) -> ShelfStore {
        guard let items = file.read([ShelfItem].self) else { return ShelfStore() }
        return ShelfStore(items: items).prunedOfMissingFiles(reachability: reachability)
    }
}
