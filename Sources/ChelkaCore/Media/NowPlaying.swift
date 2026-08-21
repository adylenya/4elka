import Foundation

public struct NowPlayingLine: Equatable {
    public let isDiff: Bool
    public let payload: [String: Any]

    public static func == (a: NowPlayingLine, b: NowPlayingLine) -> Bool {
        a.isDiff == b.isDiff && NSDictionary(dictionary: a.payload).isEqual(to: b.payload)
    }

    public static func parse(_ jsonLine: String) -> NowPlayingLine? {
        guard let data = jsonLine.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["payload"] as? [String: Any] else { return nil }
        return NowPlayingLine(isDiff: root["diff"] as? Bool ?? false, payload: payload)
    }
}

public struct NowPlaying: Equatable, Sendable {
    public let title: String?
    public let artist: String?
    public let album: String?
    public let duration: TimeInterval?
    public let elapsedAnchor: TimeInterval?
    public let anchorTimestamp: Date?
    public let isPlaying: Bool
    public let bundleIdentifier: String?
    public let artworkData: Data?

    public static let empty = NowPlaying(title: nil, artist: nil, album: nil, duration: nil,
                                         elapsedAnchor: nil, anchorTimestamp: nil,
                                         isPlaying: false, bundleIdentifier: nil, artworkData: nil)

    public var isEmpty: Bool { title == nil && artist == nil }

    /// Идентичность трека — название плюс исполнитель. Не contentItemIdentifier:
    /// он меняется при каждом обновлении состояния, что превратило бы карточку
    /// смены трека в мигалку раз в несколько секунд.
    public var trackIdentity: String? {
        guard title != nil || artist != nil else { return nil }
        return "\(title ?? "")—\(artist ?? "")"
    }

    public func position(at now: Date) -> TimeInterval? {
        guard let anchor = elapsedAnchor else { return nil }
        guard isPlaying, let stamp = anchorTimestamp else { return anchor }
        let value = anchor + now.timeIntervalSince(stamp)
        guard let duration else { return max(0, value) }
        return min(max(0, value), duration)
    }

    public func applying(_ line: NowPlayingLine) -> NowPlaying {
        let base = line.isDiff ? self : NowPlaying.empty
        let p = line.payload

        // Ключ есть, но тип не тот — это сломанный формат на той стороне, а не
        // отсутствие значения. Молчать нельзя: без сигнала будущая смена формата
        // в macOS проявится как «плеер разучился показывать длительность» без
        // единой зацепки в логах.
        // NSNull — это честное «поле очищено», а не сломанный тип: в потоке диффов
        // так штатно сбрасывают значение. Ругаться на него значит засорять лог ложной
        // тревогой ровно там, где мы хотели видеть настоящую.
        func warnIfPresentButWrongType(_ key: String) {
            guard let value = p[key], !(value is NSNull) else { return }
            NSLog("4elka: поле %@ в потоке плеера пришло неожиданного типа", key)
        }
        func str(_ key: String, _ fallback: String?) -> String? {
            if let value = p[key] as? String { return value }
            warnIfPresentButWrongType(key)
            return line.isDiff ? fallback : nil
        }
        func num(_ key: String, _ fallback: TimeInterval?) -> TimeInterval? {
            if let value = (p[key] as? NSNumber)?.doubleValue { return value }
            warnIfPresentButWrongType(key)
            return line.isDiff ? fallback : nil
        }

        // Опорная позиция и опорное время — ОДНА величина, а не две.
        // Замерено на фикстуре: последняя строка потока приносит свежий timestamp
        // без elapsedTime. Если обновить время, оставив старую позицию, живая позиция
        // навсегда занижается на этот разрыв. Поэтому пара двигается только целиком
        // и только когда пришла позиция; иначе остаётся прежней — от старой пары
        // позиция считается верно, ведь трек всё это время играл.
        let anchor: (elapsed: TimeInterval?, stamp: Date?)
        if let elapsed = (p["elapsedTime"] as? NSNumber)?.doubleValue {
            let raw = p["timestamp"] as? String
            if raw == nil { warnIfPresentButWrongType("timestamp") }
            anchor = (elapsed, raw.flatMap { ISO8601DateFormatter().date(from: $0) })
        } else if line.isDiff {
            // Именно эти два поля меняются чаще всего при смене формата в системе,
            // поэтому молчать о них нельзя — их разбор идёт отдельной ветвью и общие
            // помощники его не прикрывают.
            warnIfPresentButWrongType("elapsedTime")
            anchor = (base.elapsedAnchor, base.anchorTimestamp)
        } else {
            anchor = (nil, nil)
        }

        let artwork: Data?
        if let raw = p["artworkData"] as? String {
            artwork = Data(base64Encoded: raw, options: .ignoreUnknownCharacters)
        } else {
            artwork = line.isDiff ? base.artworkData : nil
        }

        return NowPlaying(
            title: str("title", base.title),
            artist: str("artist", base.artist),
            album: str("album", base.album),
            duration: num("duration", base.duration),
            elapsedAnchor: anchor.elapsed,
            anchorTimestamp: anchor.stamp,
            isPlaying: p["playing"] as? Bool ?? (line.isDiff ? base.isPlaying : false),
            bundleIdentifier: str("bundleIdentifier", base.bundleIdentifier),
            artworkData: artwork)
    }
}
