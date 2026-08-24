import Foundation

/// Один файл на полке. Полка хранит **ссылку** на чужой файл, а не копию:
/// `url` показывает на то, что лежит в Finder у человека, и файл может уехать
/// или исчезнуть без нашего ведома. Отсюда `prunedOfMissingFiles`.
public struct ShelfItem: Equatable, Codable, Identifiable, Sendable {
    public let id: UUID
    public let url: URL
    public let addedAt: Date
    /// Том, на котором лежит файл, сейчас не подключён: NAS уснул, внешний диск
    /// вынули. Про такой файл мы ничего не знаем — ни что он есть, ни что его
    /// удалили, — поэтому запись остаётся, но помечается.
    ///
    /// Это наблюдение, а не хранимое поле: на диск оно не пишется (см. ниже
    /// `CodingKeys`), и на каждой перепроверке спрашивается заново. Иначе
    /// пометка переживала бы возвращение тома и висела бы соврамши.
    public let isVolumeUnavailable: Bool

    public var name: String { url.lastPathComponent }

    public init(id: UUID = UUID(), url: URL, addedAt: Date, isVolumeUnavailable: Bool = false) {
        self.id = id
        self.url = url
        self.addedAt = addedAt
        self.isVolumeUnavailable = isVolumeUnavailable
    }

    /// Иммутабельно, как и всё остальное состояние: помеченная запись — новый
    /// экземпляр, мутирующих методов нет.
    public func markingVolumeUnavailable(_ flag: Bool) -> ShelfItem {
        ShelfItem(id: id, url: url, addedAt: addedAt, isVolumeUnavailable: flag)
    }

    /// Записывается и читается только то, что действительно принадлежит полке.
    /// Пометка о томе в этот список не входит намеренно.
    private enum CodingKeys: String, CodingKey { case id, url, addedAt }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        url = try container.decode(URL.self, forKey: .url)
        addedAt = try container.decode(Date.self, forKey: .addedAt)
        isVolumeUnavailable = false
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(url, forKey: .url)
        try container.encode(addedAt, forKey: .addedAt)
    }
}

/// Полка: файлы, брошенные на челку, лежат тут до явного удаления.
///
/// Это отдельное хранилище, а не вкладка истории буфера. Вкладка «Файлы»
/// в панели показывает *скопированные* файлы и подчиняется квотам истории,
/// а элемент полки не вытесняется никогда — человек положил его руками
/// и заберёт руками.
///
/// Иммутабельна, как и остальное состояние: каждое изменение возвращает
/// новый экземпляр, мутирующих методов нет.
public struct ShelfStore: Equatable, Sendable {
    public let items: [ShelfItem]

    public init(items: [ShelfItem] = []) { self.items = items }

    /// Новые файлы встают в начало: сверху то, что бросили последним.
    /// Повторный сброс того же файла поднимает его наверх, а не заводит
    /// вторую запись — двух одинаковых плиток на полке быть не должно.
    public func adding(_ urls: [URL], now: Date) -> ShelfStore {
        urls.reduce(self) { $0.inserting($1, now: now) }
    }

    public func removing(_ id: UUID) -> ShelfStore {
        ShelfStore(items: items.filter { $0.id != id })
    }

    /// Полка хранит ссылки, а не копии: исчезнувшие файлы надо выметать,
    /// иначе перетаскивание из полки будет молча отдавать пустоту.
    ///
    /// Выметается ТОЛЬКО то, чего действительно нет на достижимом пути.
    /// Недостижимый том — не повод: запись остаётся с пометкой. Раньше вопрос
    /// был двоичным («есть или нет»), уснувший NAS отвечал «нет», запись
    /// выметалась, файл полки перезаписывался — и вернувшийся том находил
    /// пустую полку.
    ///
    /// Проверка передаётся снаружи по двум причинам. Во-первых, её надо
    /// уметь подделать в тесте: тест не должен зависеть от того, что
    /// смонтировано на машине. Во-вторых, настоящая проверка на сетевом или
    /// вынутом съёмном томе отвечает долго, и звать её обязательно вне
    /// главной очереди — см. `ShelfCoordinator.pruneMissingFiles`.
    public func prunedOfMissingFiles(reachability: (URL) -> FileReachability) -> ShelfStore {
        ShelfStore(items: items.compactMap { item in
            switch reachability(item.url) {
            case .present: return item.markingVolumeUnavailable(false)
            case .missing: return nil
            case .volumeUnavailable: return item.markingVolumeUnavailable(true)
            }
        })
    }

    private func inserting(_ url: URL, now: Date) -> ShelfStore {
        let key = Self.identity(of: url)
        return ShelfStore(items: [ShelfItem(url: url, addedAt: now)]
            + items.filter { Self.identity(of: $0.url) != key })
    }

    /// Чем один файл отличается от другого. Один и тот же файл приходит
    /// записанным по-разному (лишний `.`, `..`, слеш на конце у каталога),
    /// и сравнение самих `URL` завело бы на полку дубликат.
    ///
    /// Симлинки нарочно не разворачиваются: `resolvingSymlinksInPath` лезет
    /// на диск, а дедуп обязан оставаться чистой функцией — иначе он повиснет
    /// на отключённом сетевом томе там, где его зовут при отрисовке.
    private static func identity(of url: URL) -> String {
        url.standardizedFileURL.path
    }
}
