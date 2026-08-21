import AppKit

/// Отправка файлов с полки по AirDrop.
///
/// Через системный механизм обмена (`NSSharingService`): выбор устройства
/// рисует сама система, и ни одного разрешения приложению для этого не нужно.
/// Своего кода поиска устройств, Bluetooth и сети здесь нет и быть не должно.
public enum AirDropSender {
    /// Отправлять нечего, если выделение пусто или файлы уже исчезли с диска:
    /// полка хранит ссылки, и ссылка могла умереть между сбросом и нажатием.
    public static func canSend(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty else { return false }
        return urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Показывает системное окно выбора устройства. Ничего не отправляет само:
    /// получателя выбирает человек, и отменить он может там же.
    @MainActor
    public static func send(_ urls: [URL]) {
        guard canSend(urls), let service = NSSharingService(named: .sendViaAirDrop) else {
            NSLog("4elka: отправлять по AirDrop нечего")
            return
        }
        service.perform(withItems: urls)
    }
}
