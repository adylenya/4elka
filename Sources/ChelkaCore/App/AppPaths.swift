import Foundation

public enum AppPaths {
    public static var support: URL {
        supportBase(candidates: FileManager.default.urls(for: .applicationSupportDirectory,
                                                         in: .userDomainMask),
                    home: FileManager.default.homeDirectoryForCurrentUser)
            .appendingPathComponent("4elka", isDirectory: true)
    }
    public static var blobs: URL { support.appendingPathComponent("blobs", isDirectory: true) }
    public static var index: URL { support.appendingPathComponent("index.json") }
    /// Полка лежит рядом с историей, но в своём файле: это отдельное
    /// хранилище со своим смыслом жизни элемента.
    public static var shelf: URL { support.appendingPathComponent("shelf.json") }
    public static var settings: URL { support.appendingPathComponent("settings.json") }
    public static var dragTemp: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("4elka-drag", isDirectory: true)
    }

    /// Каталог, внутри которого живут наши данные. Раньше здесь стояло обращение
    /// к нулевому элементу списка — на пустом ответе системы приложение падало
    /// прямо на старте, ещё до того, как человек увидел бы хоть что-то.
    ///
    /// Падать тут не за что: канонический путь известен и строится от домашнего
    /// каталога. Чистая функция от ответа системы — поэтому запасной путь можно
    /// проверить тестом, а не ждать редкого сбоя на живой машине.
    static func supportBase(candidates: [URL], home: URL) -> URL {
        if let named = candidates.first { return named }
        NSLog("4elka: система не назвала каталог Application Support, берём путь от домашнего каталога")
        return home.appendingPathComponent("Library/Application Support", isDirectory: true)
    }
}
