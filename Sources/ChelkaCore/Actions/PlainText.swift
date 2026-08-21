import AppKit

public enum PlainText {
    /// Снимает форматирование: из буфера берём размеченные данные и отдаём голый текст.
    public static func strip(_ attributed: Data?, fallback: String) -> String {
        guard let data = attributed,
              let string = try? NSAttributedString(
                  data: data,
                  options: [.documentType: NSAttributedString.DocumentType.rtf],
                  documentAttributes: nil),
              !string.string.isEmpty else { return fallback }
        return string.string
    }
}
