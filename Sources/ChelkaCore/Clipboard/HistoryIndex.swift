import Foundation

public struct HistoryIndex {
    private let fileURL: URL
    private let blobs: BlobStore
    private let fm = FileManager.default

    public init(fileURL: URL, blobs: BlobStore) {
        self.fileURL = fileURL
        self.blobs = blobs
    }

    public func save(_ store: HistoryStore) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try AtomicFile.write(try encoder.encode(store.items), to: fileURL)
    }

    /// Пустая история — это только отсутствие файла, и ничего больше.
    ///
    /// Файл, который есть, но не читается или не разбирается, подменять пустой
    /// историей нельзя: следующая же запись затрёт его, и все записи исчезнут
    /// навсегда. Так выглядит и недописанный файл (кончилось место, паника ядра),
    /// и будущая смена схемы `ClipItem` — тогда история пропадала бы при каждом
    /// обновлении приложения. Поэтому испорченный файл откладывается в сторону
    /// под именем `<имя>.broken-<время>`: человек может достать оттуда записи
    /// руками, а приложение начинает с чистого листа, ничего не уничтожив.
    ///
    /// Элементы с пропавшими блобами отбрасываются: стор самолечится.
    public func load() -> HistoryStore {
        guard fm.fileExists(atPath: fileURL.path) else { return HistoryStore() }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            NSLog("4elka: индекс истории есть, но не читается: %@", String(describing: error))
            setAsideBrokenIndex(now: Date())
            return HistoryStore()
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let items = try decoder.decode([ClipItem].self, from: data)
            return HistoryStore(items: items.filter { item in
                guard let name = item.blobName else { return true }
                return blobs.exists(name)
            })
        } catch {
            NSLog("4elka: индекс истории не разбирается: %@", String(describing: error))
            setAsideBrokenIndex(now: Date())
            return HistoryStore()
        }
    }

    /// Переносит испорченный файл рядом, под именем с меткой времени. Если и это
    /// не удалось — говорим прямо, что данные под угрозой: молчать здесь значит
    /// обещать сохранность, которой нет.
    private func setAsideBrokenIndex(now: Date) {
        let target = uniqueTarget(base: Self.brokenName(for: fileURL.lastPathComponent, at: now))
        do {
            try fm.moveItem(at: fileURL, to: target)
            NSLog("4elka: испорченный индекс истории отложен в %@ — записи можно достать оттуда",
                  target.lastPathComponent)
        } catch {
            NSLog("4elka: испорченный индекс не удалось отложить в сторону, он будет затёрт первой же записью: %@",
                  String(describing: error))
        }
    }

    /// Два запуска в одну и ту же секунду не должны затирать друг другу отложенный
    /// файл — на такой случай к имени добавляется различитель.
    private func uniqueTarget(base: String) -> URL {
        let directory = fileURL.deletingLastPathComponent()
        let plain = directory.appendingPathComponent(base)
        guard fm.fileExists(atPath: plain.path) else { return plain }
        return directory.appendingPathComponent("\(base)-\(UUID().uuidString)")
    }

    /// Имя отложенного файла: исходное имя целиком плюс метка времени. Чистая
    /// функция — проверяется тестом, а не глазами по каталогу. Локаль фиксирована
    /// (`en_US_POSIX`), чтобы чужой календарь в системных настройках не превратил
    /// год в 1447.
    static func brokenName(for fileName: String, at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: Config.timezone)
        formatter.dateFormat = Config.History.brokenIndexDateFormat
        return "\(fileName).\(Config.History.brokenIndexSuffix)-\(formatter.string(from: date))"
    }
}
