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

    /// Снести всё содержимое каталога. Нужно очистке истории: удалять только
    /// то, на что ссылается индекс, недостаточно — файл, потерявший запись
    /// (сбой на середине, правка индекса руками), остался бы навсегда, а
    /// человек, нажавший «Очистить историю», вправе ожидать пустоту.
    public func removeAll() {
        let names = (try? fm.contentsOfDirectory(atPath: root.path)) ?? []
        delete(names)
    }
}
