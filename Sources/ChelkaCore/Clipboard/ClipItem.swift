import Foundation

public struct ClipItem: Identifiable, Equatable, Codable {
    public struct ImageRef: Equatable, Codable {
        public let blobName: String
        public let byteCount: Int
        public let pixelSize: CGSize
        public init(blobName: String, byteCount: Int, pixelSize: CGSize) {
            self.blobName = blobName
            self.byteCount = byteCount
            self.pixelSize = pixelSize
        }
    }

    public enum Kind: Equatable, Codable {
        case text(String)
        case image(ImageRef)
        case files([URL])
    }

    public let id: UUID
    public let kind: Kind
    public let sourceAppBundleID: String?
    public let createdAt: Date
    public let contentHash: String
    public let isPinned: Bool

    public init(id: UUID, kind: Kind, sourceAppBundleID: String?,
                createdAt: Date, contentHash: String, isPinned: Bool) {
        self.id = id
        self.kind = kind
        self.sourceAppBundleID = sourceAppBundleID
        self.createdAt = createdAt
        self.contentHash = contentHash
        self.isPinned = isPinned
    }

    public var isImage: Bool { if case .image = kind { return true }; return false }
    public var isFiles: Bool { if case .files = kind { return true }; return false }

    public var blobName: String? {
        if case .image(let ref) = kind { return ref.blobName }
        return nil
    }

    /// Забирает у предыдущей записи то, что принадлежит пользователю, а не буферу:
    /// её идентификатор и признак закрепления. Всё остальное остаётся новым.
    func inheritingIdentity(from previous: ClipItem) -> ClipItem {
        ClipItem(id: previous.id, kind: kind, sourceAppBundleID: sourceAppBundleID,
                 createdAt: createdAt, contentHash: contentHash, isPinned: previous.isPinned)
    }

    func withPinned(_ pinned: Bool) -> ClipItem {
        ClipItem(id: id, kind: kind, sourceAppBundleID: sourceAppBundleID,
                 createdAt: createdAt, contentHash: contentHash, isPinned: pinned)
    }
}
