import Foundation

/// Сколько места занимает то, что приложение сложило на диск. Нужно разделу
/// «Данные» в настройках: человек должен видеть размер до того, как решит
/// нажать «Очистить историю».
public enum StorageUsage {
    /// Суммарный размер указанных путей. Каталоги считаются вместе с
    /// содержимым, отсутствующие пути — как ноль: до первого копирования ни
    /// индекса, ни каталога блобов на диске нет, и это не ошибка.
    ///
    /// Один и тот же файл, переданный дважды, считается один раз — иначе
    /// пересекающиеся пути удваивали бы размер.
    public static func bytes(of urls: [URL]) -> Int {
        var counted = Set<String>()
        var total = 0
        for url in urls {
            for file in files(at: url) where counted.insert(file.path).inserted {
                total += size(of: file)
            }
        }
        return total
    }

    /// Человеческая подпись размера. Локаль системная — числа и единицы должны
    /// читаться так же, как в Finder.
    public static func formatted(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: Int64(bytes))
    }

    /// Файлы по пути: сам путь, если это файл, или всё его содержимое, если
    /// каталог. Симлинки не разворачиваются: иначе ссылка наружу дала бы в
    /// размере каталога приложения чужие файлы.
    private static func files(at url: URL) -> [URL] {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return [] }
        guard isDirectory.boolValue else { return [url] }
        guard let walker = fm.enumerator(at: url,
                                         includingPropertiesForKeys: [.isRegularFileKey],
                                         options: [.skipsHiddenFiles,
                                                   .skipsPackageDescendants]) else { return [] }
        return walker.compactMap { $0 as? URL }.filter { file in
            (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
        }
    }

    private static func size(of file: URL) -> Int {
        (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
    }
}
