import Foundation

/// Запись через временный файл: обрыв на середине не оставит половину индекса.
public enum AtomicFile {
    /// Права записываемого файла: читать и писать может только владелец.
    /// История хранится открытым текстом, и в неё попадает всё скопированное —
    /// включая то, что копировать не стоило. По умолчанию файл создавался
    /// доступным на чтение всем, кто есть на машине.
    private static let ownerOnly = 0o600

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
            // Права ставятся дважды не по недосмотру. На временном файле — чтобы
            // содержимое ни мгновения не лежало открытым всем; на итоговом —
            // потому что подмена существующего файла сохраняет часть его
            // прежних свойств, и однажды созданный файл с правами 0644 иначе
            // остался бы таким навсегда.
            try fm.setAttributes([.posixPermissions: ownerOnly], ofItemAtPath: tmp.path)
            if fm.fileExists(atPath: url.path) {
                _ = try fm.replaceItemAt(url, withItemAt: tmp)
            } else {
                try fm.moveItem(at: tmp, to: url)
            }
            try fm.setAttributes([.posixPermissions: ownerOnly], ofItemAtPath: url.path)
        } catch {
            try? fm.removeItem(at: tmp)
            throw error
        }
    }
}
