import Foundation

/// Полка на диске. Пишется атомарно, читается терпимо: обрыв записи не должен
/// оставить половину файла, а битый файл — уронить приложение.
public struct ShelfIndex: Sendable {
    private let fileURL: URL

    public init(fileURL: URL) { self.fileURL = fileURL }

    public func save(_ store: ShelfStore) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try AtomicFile.write(try encoder.encode(store.items), to: fileURL)
    }

    /// Настоящая проверка файловой системы. Зовётся вне главной очереди —
    /// см. `ShelfCoordinator.load`.
    public func load() -> ShelfStore {
        load(fileExists: Self.fileExistsOnDisk)
    }

    /// Битый или отсутствующий файл — не ошибка, а пустая полка. Записи
    /// с пропавшими файлами отбрасываются: полка самолечится, как и история.
    ///
    /// Проверка существования вынесена в параметр ради тестов: они не должны
    /// зависеть от того, что лежит на настоящем диске.
    public func load(fileExists: (URL) -> Bool) -> ShelfStore {
        guard let data = try? Data(contentsOf: fileURL) else { return ShelfStore() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let items = try? decoder.decode([ShelfItem].self, from: data) else {
            return ShelfStore()
        }
        return ShelfStore(items: items).prunedOfMissingFiles(fileExists: fileExists)
    }

    /// Каталог тоже существует: брошенную на челку папку выметать нельзя.
    public static func fileExistsOnDisk(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}
