import Foundation

public enum AppPaths {
    public static var support: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("4elka", isDirectory: true)
    }
    public static var blobs: URL { support.appendingPathComponent("blobs", isDirectory: true) }
    public static var index: URL { support.appendingPathComponent("index.json") }
    public static var settings: URL { support.appendingPathComponent("settings.json") }
    public static var dragTemp: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("4elka-drag", isDirectory: true)
    }
}
