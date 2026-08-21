import Foundation

public struct ActivityEvent: Equatable, Identifiable, Sendable {
    /// Порядок значений задаёт приоритет: заряд важнее буфера, буфер важнее трека.
    public enum Kind: Int, Comparable, Sendable {
        case track = 0, clipboard = 1, battery = 2
        public static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }
    }

    public let id: UUID
    public let kind: Kind
    public let title: String
    public let subtitle: String?
    public let imageBlobName: String?

    public init(id: UUID = UUID(), kind: Kind, title: String,
                subtitle: String? = nil, imageBlobName: String? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.imageBlobName = imageBlobName
    }
}
