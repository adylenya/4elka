import Foundation

public struct HistoryStore: Equatable {
    public let items: [ClipItem]

    public init(items: [ClipItem] = []) { self.items = items }

    /// Повторное копирование того же содержимого поднимает элемент наверх.
    /// «Поднимает» здесь означает слияние, а не замену: у существующей записи
    /// наследуются `id` и `isPinned`, а полезная нагрузка, время и приложение-источник
    /// берутся новые.
    ///
    /// Почему именно так. Наследовать закрепление обязательно: иначе пользователь,
    /// закрепивший элемент и позже скопировавший то же самое ещё раз, молча терял бы
    /// закрепление, и элемент снова становился бы вытесняемым — стор нарушал бы
    /// собственную гарантию «закреплённое не вытесняется никогда».
    /// А нагрузку берём новую (вместе с новым блобом), чтобы старый блоб попал
    /// в `evictedBlobNames` и был удалён с диска. При обратном выборе новый блоб,
    /// уже записанный на диск до дедупа, остался бы висеть навсегда.
    public func inserting(_ item: ClipItem) -> HistoryStore {
        let existing = items.first { $0.contentHash == item.contentHash }
        let merged = existing.map { item.inheritingIdentity(from: $0) } ?? item
        var next = items.filter { $0.contentHash != item.contentHash }
        next.insert(merged, at: 0)
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

private extension ClipItem {
    var quotaBucket: QuotaBucket {
        switch kind {
        case .text: return .text
        case .image: return .image
        case .files: return .files
        }
    }
}

enum QuotaBucket {
    case text, image, files

    var limit: Int {
        switch self {
        case .text: return Config.History.textLimit
        case .image: return Config.History.imageLimit
        case .files: return Config.History.fileLimit
        }
    }
}
