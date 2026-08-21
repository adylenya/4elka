import Foundation

/// Настройки на диске: JSON рядом с историей, запись через `AtomicFile`.
///
/// Обрыв записи не должен оставлять половину файла, а битый или отсутствующий
/// файл читается как значения по умолчанию, а не роняет приложение при старте.
/// Прочитанное прогоняется через `sanitized()`: файл могли поправить руками.
public final class SettingsStore: Sendable {
    private let fileURL: URL

    public init(fileURL: URL) { self.fileURL = fileURL }

    public func load() -> Settings {
        guard let data = try? Data(contentsOf: fileURL) else { return .defaults }
        guard let settings = try? JSONDecoder().decode(Settings.self, from: data) else {
            // Молчать нельзя: иначе настройки «сами сбросились», и понять
            // почему — неоткуда.
            NSLog("4elka: файл настроек не читается, берём значения по умолчанию")
            return .defaults
        }
        return settings.sanitized()
    }

    public func save(_ settings: Settings) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try AtomicFile.write(try encoder.encode(settings), to: fileURL)
        } catch {
            NSLog("4elka: не удалось сохранить настройки: %@", String(describing: error))
        }
    }
}
