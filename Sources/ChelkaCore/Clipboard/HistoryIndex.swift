import Foundation

public struct HistoryIndex {
    private let fileURL: URL
    private let blobs: BlobStore

    public init(fileURL: URL, blobs: BlobStore) {
        self.fileURL = fileURL
        self.blobs = blobs
    }

    public func save(_ store: HistoryStore) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try AtomicFile.write(try encoder.encode(store.items), to: fileURL)
    }

    /// Битый или отсутствующий индекс — не ошибка, а пустая история.
    /// Элементы с пропавшими блобами отбрасываются: стор самолечится.
    public func load() -> HistoryStore {
        guard let data = try? Data(contentsOf: fileURL) else { return HistoryStore() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let items = try? decoder.decode([ClipItem].self, from: data) else {
            return HistoryStore()
        }
        return HistoryStore(items: items.filter { item in
            guard let name = item.blobName else { return true }
            return blobs.exists(name)
        })
    }
}
