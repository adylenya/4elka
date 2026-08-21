import Foundation

public struct BlobStore {
    private let root: URL
    private let fm = FileManager.default

    public init(root: URL) { self.root = root }

    public func write(_ data: Data, extension ext: String) throws -> String {
        let name = "\(UUID().uuidString).\(ext)"
        try AtomicFile.write(data, to: root.appendingPathComponent(name))
        return name
    }

    /// Имя блоба приходит из индекса на диске, то есть из данных, а не только из кода.
    /// Битый или подменённый индекс может принести «../../что-то», и системный вызов
    /// удаления раскрутит эти «..» уже вне нашего каталога — то есть снесёт чужой файл.
    /// Поэтому от имени берётся только последний компонент пути, всегда.
    private func safeName(_ blobName: String) -> String {
        (blobName as NSString).lastPathComponent
    }

    public func url(for blobName: String) -> URL {
        root.appendingPathComponent(safeName(blobName))
    }

    public func exists(_ blobName: String) -> Bool {
        fm.fileExists(atPath: url(for: blobName).path)
    }

    public func delete(_ blobNames: [String]) {
        for name in blobNames { try? fm.removeItem(at: url(for: name)) }
    }

    /// Что лежит в каталоге сейчас — с временем изменения каждого файла.
    /// Нужно уборке: решить, какие файлы осиротели, можно только сравнив каталог
    /// со ссылками из истории.
    ///
    /// Отсутствующий каталог — обычное дело до первой картинки, это пустой
    /// список, а не ошибка. Всё остальное попадает в лог: молча вернуть пустой
    /// список значило бы выдать нечитаемый каталог за убранный.
    public func files() -> [BlobGarbage.File] {
        guard fm.fileExists(atPath: root.path) else { return [] }
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        let contents: [URL]
        do {
            contents = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: Array(keys))
        } catch {
            NSLog("4elka: каталог картинок не читается, уборка пропущена: %@",
                  String(describing: error))
            return []
        }
        return contents.compactMap { url in
            guard let modified = try? url.resourceValues(forKeys: keys).contentModificationDate else {
                // Без времени изменения возраст не посчитать, а без возраста
                // файл удалять нельзя — он может быть только что записанным.
                NSLog("4elka: у файла %@ не читается время изменения, уборка его не трогает",
                      url.lastPathComponent)
                return nil
            }
            return BlobGarbage.File(name: url.lastPathComponent, modifiedAt: modified)
        }
    }
}
