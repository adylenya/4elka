import Foundation

/// Уборщик временного каталога перетаскивания.
///
/// Зачем он нужен. `DragMaterializer` кладёт туда копии блобов и текстовые
/// огрызки под человеческими именами, а получатель жеста (Finder, почта,
/// мессенджер) копирует файл к себе и оригинал не забирает. Удалить его
/// сразу после жеста нельзя — получатель читает файл уже после того, как
/// кнопку мыши отпустили. Значит, чистить надо позже и по возрасту, иначе
/// каталог растёт до конца жизни системы.
public struct DragTempCleaner {
    private let root: URL
    private let lifetime: TimeInterval
    private let fm = FileManager.default

    public init(root: URL, lifetime: TimeInterval = Config.Drag.tempLifetime) {
        self.root = root
        self.lifetime = lifetime
    }

    /// Удаляет всё, что старше `lifetime`. Свежее не трогает: жест мог ещё
    /// не завершиться. Отсутствие каталога — не сбой, а «убирать нечего»:
    /// до первого перетаскивания его вообще не существует.
    public func sweep(now: Date) {
        guard let entries = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { return }
        for url in entries where isStale(url, now: now) {
            do {
                try fm.removeItem(at: url)
            } catch {
                // Не смогли удалить — это утечка места, и молчать о ней нельзя.
                NSLog("4elka: не удалось убрать файл жеста %@: %@",
                      url.lastPathComponent, String(describing: error))
            }
        }
    }

    /// Возраст берётся из даты изменения файла. Если её не отдали — считаем
    /// файл свежим: удалить чужое по незнанию хуже, чем оставить своё.
    private func isStale(_ url: URL, now: Date) -> Bool {
        guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate else { return false }
        return now.timeIntervalSince(modified) > lifetime
    }
}
