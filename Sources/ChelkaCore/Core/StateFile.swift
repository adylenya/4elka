import Foundation

/// Файл состояния на диске: пишется атомарно, читается терпимо.
///
/// Пустое состояние — это только отсутствие файла, и ничего больше. Файл,
/// который есть, но не читается или не разбирается, подменять пустым нельзя:
/// следующая же запись затрёт его, и все записи исчезнут навсегда. Так выглядит
/// и недописанный файл (кончилось место, потеря питания), и будущая смена схемы —
/// тогда данные пропадали бы при каждом обновлении приложения. Поэтому
/// испорченный файл откладывается в сторону под именем `<имя>.broken-<время>`:
/// человек может достать записи руками, а приложение начинает с чистого листа,
/// ничего не уничтожив.
///
/// Один тип на всё приложение, а не по копии на хранилище: полка когда-то
/// обходилась своей наивной парой `try?` и теряла содержимое ровно в том
/// сценарии, от которого история была защищена.
public struct StateFile: Sendable {
    private let fileURL: URL
    /// Как звать этот файл в логе. Человеку, читающему Console, «полка» говорит
    /// больше, чем путь до `~/Library/Application Support`.
    private let subject: String

    public init(fileURL: URL, subject: String) {
        self.fileURL = fileURL
        self.subject = subject
    }

    public func write<Value: Encodable>(_ value: Value) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try AtomicFile.write(try encoder.encode(value), to: fileURL)
    }

    /// `nil` — начинать с чистого листа: файла либо нет вовсе, либо он был
    /// испорчен и уже отложен в сторону.
    public func read<Value: Decodable>(_ type: Value.Type, now: Date = Date()) -> Value? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            NSLog("4elka: %@ есть, но не читается: %@", subject, String(describing: error))
            setAsideBroken(now: now)
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(Value.self, from: data)
        } catch {
            NSLog("4elka: %@ не разбирается: %@", subject, String(describing: error))
            setAsideBroken(now: now)
            return nil
        }
    }

    /// Переносит испорченный файл рядом, под именем с меткой времени. Если и это
    /// не удалось — говорим прямо, что данные под угрозой: молчать здесь значит
    /// обещать сохранность, которой нет.
    private func setAsideBroken(now: Date) {
        let fm = FileManager.default
        let target = uniqueTarget(base: Self.brokenName(for: fileURL.lastPathComponent, at: now))
        do {
            try fm.moveItem(at: fileURL, to: target)
            NSLog("4elka: испорченный файл (%@) отложен в %@ — записи можно достать оттуда",
                  subject, target.lastPathComponent)
        } catch {
            NSLog("4elka: испорченный файл (%@) не удалось отложить в сторону, он будет затёрт первой же записью: %@",
                  subject, String(describing: error))
        }
    }

    /// Два запуска в одну и ту же секунду не должны затирать друг другу отложенный
    /// файл — на такой случай к имени добавляется различитель.
    private func uniqueTarget(base: String) -> URL {
        let fm = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        let plain = directory.appendingPathComponent(base)
        guard fm.fileExists(atPath: plain.path) else { return plain }
        return directory.appendingPathComponent("\(base)-\(UUID().uuidString)")
    }

    /// Имя отложенного файла: исходное имя целиком плюс метка времени. Чистая
    /// функция — проверяется тестом, а не глазами по каталогу. Локаль фиксирована
    /// (`en_US_POSIX`), чтобы чужой календарь в системных настройках не превратил
    /// год в 1447.
    public static func brokenName(for fileName: String, at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: Config.timezone)
        formatter.dateFormat = Config.StateFile.brokenDateFormat
        return "\(fileName).\(Config.StateFile.brokenSuffix)-\(formatter.string(from: date))"
    }
}
