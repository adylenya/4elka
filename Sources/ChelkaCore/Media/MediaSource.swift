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
