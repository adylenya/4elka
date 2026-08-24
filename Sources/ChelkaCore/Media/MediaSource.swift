import Foundation

/// `Sendable` объявлено явно: у публичного типа это не выводится само, а
/// команда ездит между очередями (интерфейс → супервизор → процесс).
public enum MediaCommand: Int, Sendable {
    case play = 0, pause = 1, toggle = 2, next = 4, previous = 5
}

/// Источник состояния плеера.
///
/// Изоляция на главный актор и приём замыканий в `start` — не украшение.
/// Раньше это были публичные изменяемые свойства неизолированного протокола:
/// писать их разрешалось откуда угодно и когда угодно, хотя читает их источник
/// с чужой очереди. Фактически писал только координатор с главного актора, то
/// есть ручное обещание потокобезопасности прикрывало настоящую дыру — и в
/// первый же день, когда кто-то поставил бы обработчик из другого потока,
/// вернулась бы гонка, которую нечем поймать.
@MainActor
public protocol MediaSource: AnyObject {
    func start(onState: @escaping @MainActor (NowPlaying) -> Void,
               onUnavailable: @escaping @MainActor () -> Void)
    func stop()
    func send(_ command: MediaCommand)
}

/// Поток приходит кусками, которые не совпадают с границами строк.
struct LineBuffer {
    private var pending = Data()
    /// Куда ругаться на выброшенное. Параметром, а не сразу `NSLog`: иначе
    /// «об этом сказано в лог» нечем проверить, и молчание вернётся незаметно.
    private let warn: (String) -> Void

    init(warn: @escaping (String) -> Void = { NSLog("4elka: %@", $0) }) {
        self.warn = warn
    }

    mutating func appending(_ chunk: Data) -> [String] {
        pending.append(chunk)
        // Сначала нарезка, и только потом порог. Наоборот было нельзя: проверка
        // до нарезки выбрасывала весь кусок целиком — вместе с валидной строкой,
        // приехавшей в нём же рядом с началом (или хвостом) очень длинной.
        // Длинные строки тут штатны: обложка идёт в потоке как base64.
        var lines: [String] = []
        while let index = pending.firstIndex(of: UInt8(ascii: "\n")) {
            let raw = pending[pending.startIndex..<index]
            pending = pending[pending.index(after: index)...]
            guard let text = String(data: raw, encoding: .utf8) else {
                // Молчать нельзя: битая кодировка в потоке — это либо поломка
                // адаптера, либо смена формата, и без строчки в логе она
                // выглядит как «плеер иногда пропускает обновления».
                warn("строка потока плеера не в UTF-8, отброшено байт: \(raw.count)")
                continue
            }
            if !text.isEmpty { lines.append(text) }
        }
        // Порог применяется только к НЕДОСОБРАННОМУ остатку: поток без единого
        // перевода строки иначе съел бы всю память. Такого не бывает при здоровом
        // адаптере — это защита от чужой поломки, а не штатный путь.
        if pending.count > Config.Media.maxPendingBytes {
            warn("поток плеера прислал \(pending.count) байт без перевода строки, сбрасываю остаток")
            pending = Data()
        }
        return lines
    }
}

/// Решение супервизора вынесено из замыканий в чистое значение — именно из-за того,
/// что раньше оно было размазано по обработчикам, баг «перезапуск срабатывает уже
/// после остановки» не поймался ни одним тестом.
public struct RestartPolicy: Equatable, Sendable {
    public let delay: TimeInterval
    public let immediateFailures: Int

    public static let initial = RestartPolicy(
        delay: Config.Media.restartDelayInitial, immediateFailures: 0)

    /// Процесс умер. `livedFor` — сколько он прожил.
    public func afterExit(livedFor lifetime: TimeInterval) -> RestartPolicy {
        if lifetime >= Config.Media.healthyRunGrace {
            return .initial
        }
        return RestartPolicy(
            delay: min(delay * 2, Config.Media.restartDelayMax),
            immediateFailures: immediateFailures + 1)
    }

    /// Столько мгновенных смертей подряд — значит адаптера нет или он сломан,
    /// и дёргать его дальше бессмысленно.
    public var shouldGiveUp: Bool {
        immediateFailures >= Config.Media.maxImmediateFailures
    }
}

/// Хвост потока ошибок адаптера.
///
/// Поток ошибок уходил в `/dev/null`, и самый вероятный сбой плеера — perl не
/// смог загрузить фреймворк — выходил наружу одной строкой «падает сразу,
/// прекращаю попытки»: без пути и без причины. Держим последние строки, чтобы
/// в лог попало то, что сказал сам адаптер перед смертью.
///
/// Накопитель байтов, как и `LineBuffer` рядом: правило иммутабельности
/// относится к типам состояния, а не к буферам, собирающим поток по кускам.
struct ErrorTail {
    private var pending = Data()
    private var lines: [String] = []

    /// Недособранная строка — ещё не строка: ждём перевода строки. Иначе
    /// огрызок, приехавший последним куском, попал бы в лог как полноценная
    /// жалоба адаптера.
    mutating func appending(_ chunk: Data) {
        pending.append(chunk)
        while let index = pending.firstIndex(of: UInt8(ascii: "\n")) {
            let raw = pending[pending.startIndex..<index]
            pending = pending[pending.index(after: index)...]
            guard let text = String(data: raw, encoding: .utf8), !text.isEmpty else { continue }
            lines.append(text)
            if lines.count > Config.Media.errorTailLines {
                lines.removeFirst(lines.count - Config.Media.errorTailLines)
            }
        }
    }

    /// `nil`, если адаптер не сказал ничего: пустая строка в логе хуже её
    /// отсутствия — она выглядит как «причина есть, но не показана».
    var text: String? { lines.isEmpty ? nil : lines.joined(separator: "\n") }
}
