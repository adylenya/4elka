import Foundation

public enum AppPaths {
    public static var support: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("4elka", isDirectory: true)
    }
    public static var blobs: URL { support.appendingPathComponent("blobs", isDirectory: true) }
    public static var index: URL { support.appendingPathComponent("index.json") }
    /// Полка лежит рядом с историей, но в своём файле: это отдельное
    /// хранилище со своим смыслом жизни элемента.
    public static var shelf: URL { support.appendingPathComponent("shelf.json") }
    public static var dragTemp: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("4elka-drag", isDirectory: true)
    }
}
