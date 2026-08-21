import Foundation

/// Сколько элементов каждого вида держит история. Значение, а не константы:
/// квоты правит человек в настройках, и стор обязан считаться с ними, а не с
/// зашитыми в код числами.
public struct HistoryQuotas: Equatable, Sendable {
    public let text: Int
    public let image: Int
    public let files: Int

    public init(text: Int, image: Int, files: Int) {
        self.text = text
        self.image = image
        self.files = files
    }

    /// Значения из `Config` — он остаётся источником истины, настройки его
    /// только перекрывают.
    public static let `default` = HistoryQuotas(text: Config.History.textLimit,
                                                image: Config.History.imageLimit,
                                                files: Config.History.fileLimit)
}

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
    public func inserting(_ item: ClipItem,
                          quotas: HistoryQuotas = .default) -> HistoryStore {
        let existing = items.first { $0.contentHash == item.contentHash }
        let merged = existing.map { item.inheritingIdentity(from: $0) } ?? item
        var next = items.filter { $0.contentHash != item.contentHash }
        next.insert(merged, at: 0)
        return HistoryStore(items: Self.applyQuotas(to: next, quotas: quotas))
    }

    /// Пересчёт квот без вставки: нужен, когда человек уменьшил квоту в
    /// настройках. Ждать следующего копирования нельзя — тогда «сколько
    /// хранить» вступало бы в силу неизвестно когда.
    public func applyingQuotas(_ quotas: HistoryQuotas) -> HistoryStore {
        HistoryStore(items: Self.applyQuotas(to: items, quotas: quotas))
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
    private static func applyQuotas(to items: [ClipItem],
                                    quotas: HistoryQuotas) -> [ClipItem] {
        var counters: [QuotaBucket: Int] = [:]
        var drop = Set<UUID>()
        for item in items where !item.isPinned {
            let bucket = item.quotaBucket
            let seen = (counters[bucket] ?? 0) + 1
            counters[bucket] = seen
            if seen > bucket.limit(quotas) { drop.insert(item.id) }
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

    func limit(_ quotas: HistoryQuotas) -> Int {
        switch self {
        case .text: return quotas.text
        case .image: return quotas.image
        case .files: return quotas.files
        }
    }
}
