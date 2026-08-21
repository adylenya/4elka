import Foundation

public enum Transformation: String, CaseIterable {
    case jsonPretty, jsonMinify, base64Encode, base64Decode
    case urlEncode, urlDecode, jwtDecode, timestampToDate

    public var title: String {
        switch self {
        case .jsonPretty: return "JSON красиво"
        case .jsonMinify: return "JSON в строку"
        case .base64Encode: return "В base64"
        case .base64Decode: return "Из base64"
        case .urlEncode: return "Экранировать для URL"
        case .urlDecode: return "Снять экранирование URL"
        case .jwtDecode: return "Разобрать JWT"
        case .timestampToDate: return "Время в дату"
        }
    }
}

public enum Transformations {
    public static func apply(_ t: Transformation, to input: String) -> String? {
        switch t {
        case .jsonPretty: return json(input, pretty: true)
        case .jsonMinify: return json(input, pretty: false)
        case .base64Encode: return Data(input.utf8).base64EncodedString()
        case .base64Decode:
            guard let data = Data(base64Encoded: input, options: .ignoreUnknownCharacters),
                  let text = String(data: data, encoding: .utf8) else { return nil }
            return text
        case .urlEncode:
            return input.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
        case .urlDecode:
            return input.removingPercentEncoding
        case .jwtDecode: return jwt(input)
        case .timestampToDate: return timestamp(input)
        }
    }

    public static func available(for input: String) -> [Transformation] {
        Transformation.allCases.filter { apply($0, to: input) != nil }
    }

    private static func json(_ input: String, pretty: Bool) -> String? {
        guard let data = input.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let options: JSONSerialization.WritingOptions = pretty
            ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            : [.withoutEscapingSlashes]
        guard let out = try? JSONSerialization.data(withJSONObject: object, options: options) else {
            return nil
        }
        return String(data: out, encoding: .utf8)
    }

    private static func jwt(_ input: String) -> String? {
        let parts = input.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        guard let payload = base64URLDecode(String(parts[1])),
              let object = try? JSONSerialization.jsonObject(with: payload),
              let pretty = try? JSONSerialization.data(withJSONObject: object,
                                                       options: [.prettyPrinted, .sortedKeys]) else {
            return nil
        }
        return String(data: pretty, encoding: .utf8)
    }

    /// В JWT используется base64url без выравнивания — обычный декодер его не берёт.
    private static func base64URLDecode(_ input: String) -> Data? {
        var s = input.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s.append("=") }
        return Data(base64Encoded: s)
    }

    private static func timestamp(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw = Double(trimmed), trimmed.allSatisfy({ $0.isNumber || $0 == "-" }) else {
            return nil
        }
        // 13 знаков — миллисекунды: иначе 1755777600000 превратится в 55-й век.
        let seconds = trimmed.count >= 12 ? raw / 1000 : raw
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: Config.timezone)
        return formatter.string(from: Date(timeIntervalSince1970: seconds))
    }
}
