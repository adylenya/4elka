import AppKit
import Foundation

/// Живая полка: состояние в памяти, файл на диске и связка с интерфейсом.
///
/// Отдельный координатор, а не `ClipboardCoordinator`: у элемента полки другой
/// смысл жизни. Клип живёт до вытеснения квотой, файл на полке — до того, как
/// человек сам его уберёт.
@MainActor
public final class ShelfCoordinator: ObservableObject {
    @Published public private(set) var shelf = ShelfStore()

    private let index: ShelfIndex

    public init(index: ShelfIndex) { self.index = index }

    /// Чтение полки целиком уходит с главной очереди: внутри настоящая
    /// проверка существования каждого файла, а файл мог остаться на сетевом
    /// или съёмном томе — такая проверка отвечает секундами, и на главной
    /// очереди она заморозила бы интерфейс на старте.
    public func load() async {
        let index = self.index
        shelf = await Task.detached(priority: .utility) { index.load() }.value
    }

    /// Перепроверка перед показом полки: пока панель была закрыта, файлы могли
    /// удалить или перенести. Уходит с главной очереди по той же причине,
    /// что и `load`.
    public func pruneMissingFiles() async {
        let snapshot = shelf
        let pruned = await Task.detached(priority: .utility) {
            snapshot.prunedOfMissingFiles(fileExists: ShelfIndex.fileExistsOnDisk)
        }.value
        guard pruned != shelf else { return }
        shelf = pruned
        save()
    }

    public func add(_ urls: [URL], now: Date = Date()) {
        guard !urls.isEmpty else { return }
        shelf = shelf.adding(urls, now: now)
        save()
    }

    public func remove(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        shelf = ids.reduce(shelf) { $0.removing($1) }
        save()
    }

    /// Файлы выделенного — в порядке выделения: в этом же порядке они уедут
    /// в жест перетаскивания и в AirDrop. Пропавшие записи молча выпадают,
    /// а не превращаются в битые ссылки.
    public func urls(for ids: [UUID]) -> [URL] {
        ids.compactMap { id in shelf.items.first { $0.id == id }?.url }
    }

    public func sendViaAirDrop(_ ids: [UUID]) {
        AirDropSender.send(urls(for: ids))
    }

    /// Полка пишется сразу и без задержки: она меняется от руки человека
    /// (сброс, удаление), а не двести раз в секунду, как история буфера, —
    /// схлопывать записи тут нечего, а потерять полку из-за выхода из
    /// приложения между изменением и записью было бы обидно.
    private func save() {
        do {
            try index.save(shelf)
        } catch {
            NSLog("4elka: полка не записалась: %@", String(describing: error))
        }
    }
}
