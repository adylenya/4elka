import Foundation

public struct HistoryStore: Equatable {
    public let items: [ClipItem]

    public init(items: [ClipItem] = []) { self.items = items }

    public func inserting(_ item: ClipItem) -> HistoryStore {
        var next = items.filter { $0.contentHash != item.contentHash }
        next.insert(item, at: 0)
        return HistoryStore(items: Self.applyQuotas(to: next))
    }

    public func pinning(_ id: UUID) -> HistoryStore { setPinned(id, true) }
    public func unpinning(_ id: UUID) -> HistoryStore { setPinned(id, false) }

    public func removing(_ id: UUID) -> HistoryStore {
        HistoryStore(items: items.filter { $0.id != id })
    }

    /// Имена блобов, которые были в previous и исчезли здесь: их файлы можно удалять.
    public func evictedBlobNames(comparedTo previous: HistoryStore) -> [String] {
        let surviving = Set(items.compactMap(\.blobName))
        return previous.items.compactMap(\.blobName).filter { !surviving.contains($0) }
    }

    private func setPinned(_ id: UUID, _ pinned: Bool) -> HistoryStore {
        HistoryStore(items: items.map { $0.id == id ? $0.withPinned(pinned) : $0 })
    }

    /// Квоты считаются раздельно по типу: картинки тяжелее текста, и общий лимит
    /// приводил бы к тому, что десяток скриншотов вытеснял бы всю текстовую историю.
    private static func applyQuotas(to items: [ClipItem]) -> [ClipItem] {
        var counters: [QuotaBucket: Int] = [:]
        var drop = Set<UUID>()
        for item in items where !item.isPinned {
            let bucket = item.quotaBucket
            let seen = (counters[bucket] ?? 0) + 1
            counters[bucket] = seen
            if seen > bucket.limit { drop.insert(item.id) }
        }
        return items.filter { !drop.contains($0.id) }
    }
}
