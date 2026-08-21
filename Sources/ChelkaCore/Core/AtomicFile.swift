import Foundation

/// Запись через временный файл: обрыв на середине не оставит половину индекса.
public enum AtomicFile {
    public static func write(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(),
                               withIntermediateDirectories: true)
        let tmp = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        // Если что-то упадёт на середине (кончилось место, отказали права), временный
        // файл обязан исчезнуть. Иначе он останется навсегда: перечислять и подчищать
        // такие огрызки больше некому, и на тысячах записей блобов это тихая утечка места.
        do {
            try data.write(to: tmp)
            if fm.fileExists(atPath: url.path) {
                _ = try fm.replaceItemAt(url, withItemAt: tmp)
            } else {
                try fm.moveItem(at: tmp, to: url)
            }
        } catch {
            try? fm.removeItem(at: tmp)
            throw error
        }
    }
}
