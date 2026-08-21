import Foundation
import Vision

public enum TextRecognition {
    /// Порядок важен: Vision использует его как приоритет подсказок.
    public static let languages = ["ru-RU", "en-US"]

    public struct MissingImage: Error {}

    public static func supportsRussian() -> Bool {
        let supported = (try? VNRecognizeTextRequest().supportedRecognitionLanguages()) ?? []
        return supported.contains { $0.hasPrefix("ru") }
    }

    public static func recognize(imageAt url: URL) throws -> String {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw MissingImage()
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages

        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])

        let observations = request.results ?? []
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}
