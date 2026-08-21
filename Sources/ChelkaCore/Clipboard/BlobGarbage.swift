import Foundation

/// Уборка каталога картинок.
///
/// Индекс самолечится в одну сторону: элементы, чьи файлы пропали, `load()`
/// отбрасывает. Обратного не делал никто — файл, на который не осталось ссылок,
/// оставался на диске навсегда. А остаться он может от каждого падения между
/// записью файла и записью индекса; потолок одной картинки — сорок мегабайт,
/// так что каталог рос неограниченно и убрать его было нечем.
public enum BlobGarbage {
    /// Файл в каталоге картинок: имя и время последнего изменения. Каталог
    /// читает `BlobStore`, решение принимается здесь — так решение остаётся
    /// чистой функцией и проверяется тестом, а не глазами по каталогу.
    public struct File: Equatable, Sendable {
        public let name: String
        public let modifiedAt: Date

        public init(name: String, modifiedAt: Date) {
            self.name = name
            self.modifiedAt = modifiedAt
        }
    }

    /// Имена файлов, которые можно удалить: на них не ссылается ни один элемент
    /// истории, и они старше `Config.History.orphanBlobGrace`.
    ///
    /// Пощада свежим — не перестраховка, а необходимость. Файл картинки ложится
    /// на диск раньше, чем индекс со ссылкой на него, и в этом зазоре его никто
    /// не удерживает: без возрастного порога уборка сносила бы картинку, которую
    /// человек только что скопировал.
    public static func collectable(files: [File], referenced: Set<String>,
                                   now: Date) -> [String] {
        files
            .filter { !referenced.contains($0.name) }
            .filter { now.timeIntervalSince($0.modifiedAt) > Config.History.orphanBlobGrace }
            .map(\.name)
    }
}
