import Foundation

public struct HistoryIndex {
    private let file: StateFile
    private let blobs: BlobStore

    public init(fileURL: URL, blobs: BlobStore) {
        self.file = StateFile(fileURL: fileURL, subject: "индекс истории")
        self.blobs = blobs
    }

    public func save(_ store: HistoryStore) throws {
        try file.write(store.items)
    }

    /// Пустая история — это только отсутствие файла, и ничего больше. Битый файл
    /// откладывается в сторону, а не подменяется пустотой: почему именно так —
    /// в `StateFile`.
    ///
    /// Элементы с пропавшими блобами отбрасываются: стор самолечится.
    public func load() -> HistoryStore {
        guard let items = file.read([ClipItem].self) else { return HistoryStore() }
        return HistoryStore(items: items.filter { item in
            guard let name = item.blobName else { return true }
            return blobs.exists(name)
        })
    }
}
