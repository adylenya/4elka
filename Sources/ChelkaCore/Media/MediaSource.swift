import Foundation

public enum MediaCommand: Int {
    case play = 0, pause = 1, toggle = 2, next = 4, previous = 5
}

public protocol MediaSource: AnyObject {
    var onState: ((NowPlaying) -> Void)? { get set }
    var onUnavailable: (() -> Void)? { get set }
    func start()
    func stop()
    func send(_ command: MediaCommand)
}

/// Поток приходит кусками, которые не совпадают с границами строк.
struct LineBuffer {
    private var pending = Data()

    mutating func appending(_ chunk: Data) -> [String] {
        pending.append(chunk)
        // Поток без единого перевода строки иначе съел бы всю память.
        // Такого не бывает при здоровом адаптере, поэтому это защита от чужой
        // поломки, а не штатный путь: недособранное выбрасываем и говорим об этом.
        if pending.count > Config.Media.maxPendingBytes {
            NSLog("4elka: поток плеера прислал %d байт без перевода строки, сбрасываю буфер",
                  pending.count)
            pending = Data()
            return []
        }
        var lines: [String] = []
        while let index = pending.firstIndex(of: UInt8(ascii: "\n")) {
            let raw = pending[pending.startIndex..<index]
            pending = pending[pending.index(after: index)...]
            if let text = String(data: raw, encoding: .utf8), !text.isEmpty {
                lines.append(text)
            }
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
