import AppKit

/// Отправка файлов с полки по AirDrop.
///
/// Через системный механизм обмена (`NSSharingService`): выбор устройства
/// рисует сама система, и ни одного разрешения приложению для этого не нужно.
/// Своего кода поиска устройств, Bluetooth и сети здесь нет и быть не должно.
public enum AirDropSender {
    /// Чем закончилась попытка. Раньше отказ уходил одной строкой в системный
    /// журнал: человек жал самолётик, окно выбора получателя не появлялось, и
    /// узнать причину можно было только через Console.
    public enum Outcome: Equatable, Sendable {
        /// Окно выбора получателя показано — дальше решает человек.
        case opened
        case nothingSelected
        /// Файлы исчезли с диска между сбросом на полку и нажатием.
        case filesGone([URL])
        /// Системный механизм обмена недоступен.
        case serviceUnavailable

        /// Что сказать человеку. `nil` — говорить нечего, всё шло как надо.
        public var message: String? {
            switch self {
            case .opened, .nothingSelected: return nil
            case .filesGone(let urls):
                let names = urls.map(\.lastPathComponent).joined(separator: ", ")
                return urls.count == 1
                    ? "Файла больше нет на диске: \(names)"
                    : "Этих файлов больше нет на диске: \(names)"
            case .serviceUnavailable:
                return "Система не отдала окно выбора получателя"
            }
        }
    }

    /// Пропавшие файлы из списка. Проверка существования **синхронная**, поэтому
    /// звать её надо вне главной очереди: на отвалившемся сетевом томе она
    /// отвечает секундами и заморозила бы интерфейс.
    public static func missingFiles(_ urls: [URL]) -> [URL] {
        urls.filter { FileReachabilityProbe.onDisk($0) != .present }
    }

    /// Показывает системное окно выбора устройства. Ничего не отправляет само:
    /// получателя выбирает человек, и отменить он может там же.
    ///
    /// Список пропавших приходит снаружи уже готовым — посчитанный в фоне.
    @MainActor
    public static func send(_ urls: [URL], missing: [URL]) -> Outcome {
        guard !urls.isEmpty else { return .nothingSelected }
        guard missing.isEmpty else { return .filesGone(missing) }
        guard let service = NSSharingService(named: .sendViaAirDrop) else {
            return .serviceUnavailable
        }
        service.perform(withItems: urls)
        return .opened
    }
}
