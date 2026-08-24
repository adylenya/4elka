import Foundation

/// Что файловая система отвечает про путь, лежащий на полке.
///
/// Три состояния, а не два, потому что «файла нет» и «тома сейчас нет» — разные
/// события с противоположными последствиями. Полка хранит ссылки, и вопрос
/// «есть или нет» на уснувшем NAS отвечает «нет» — а запись после этого
/// выметалась и файл полки тут же перезаписывался. Вернувшийся том находил
/// пустую полку, и восстановить её было нечем.
public enum FileReachability: Equatable, Sendable {
    /// Путь достижим, файл (или каталог) на месте.
    case present
    /// Путь достижим, а файла нет: его удалили или перенесли. Запись выметается.
    case missing
    /// Тома нет: NAS уснул, отвалился Wi-Fi, внешний диск вынули. Запись
    /// остаётся и помечается — про такой файл мы просто ничего не знаем.
    case volumeUnavailable
}

/// Настоящая проверка достижимости. Разделена нарочно: «какой том подразумевает
/// путь» — чистая функция, её проверяет тест; «что сейчас смонтировано» — вопрос
/// к системе, и в тесте он подделывается. Иначе тест зависел бы от того, что
/// висит в `/Volumes` на машине, где его запускают.
public enum FileReachabilityProbe {
    /// Зовётся вне главной очереди — см. `ShelfCoordinator.pruneMissingFiles`:
    /// на отвалившемся сетевом томе проверка отвечает секундами.
    public static func onDisk(_ url: URL) -> FileReachability {
        reachability(of: url,
                     fileExists: { FileManager.default.fileExists(atPath: $0.path) },
                     mountedVolumes: mountedVolumePaths())
    }

    /// Каталог тоже существует: брошенную на челку папку выметать нельзя,
    /// поэтому проверка именно на существование пути, а не на файл.
    static func reachability(of url: URL,
                             fileExists: (URL) -> Bool,
                             mountedVolumes: Set<String>) -> FileReachability {
        if fileExists(url) { return .present }
        // Загрузочный том всегда на месте: там пропавший файл пропал всерьёз.
        guard let volume = volumeRoot(of: url) else { return .missing }
        return mountedVolumes.contains(volume) ? .missing : .volumeUnavailable
    }

    /// Том, который подразумевает путь, или `nil` для загрузочного. Съёмные
    /// и сетевые тома macOS монтирует в `/Volumes/<имя>`, и вынутый диск
    /// уносит с собой весь этот подкаталог целиком — значит по пути видно,
    /// какой том надо искать в списке смонтированных.
    static func volumeRoot(of url: URL) -> String? {
        let parts = url.standardizedFileURL.pathComponents
        let root = URL(fileURLWithPath: Config.Shelf.volumesRoot).standardizedFileURL.pathComponents
        guard parts.count > root.count, Array(parts.prefix(root.count)) == root else { return nil }
        return NSString.path(withComponents: Array(parts.prefix(root.count + 1)))
    }

    static func mountedVolumePaths() -> Set<String> {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil,
                                                        options: []) ?? []
        return Set(urls.map { $0.standardizedFileURL.path })
    }
}
