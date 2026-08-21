import Foundation

public struct BlobStore {
    private let root: URL
    private let fm = FileManager.default

    public init(root: URL) { self.root = root }

    public func write(_ data: Data, extension ext: String) throws -> String {
        let name = "\(UUID().uuidString).\(ext)"
        try AtomicFile.write(data, to: root.appendingPathComponent(name))
        return name
    }

    public func url(for blobName: String) -> URL { root.appendingPathComponent(blobName) }
    public func exists(_ blobName: String) -> Bool { fm.fileExists(atPath: url(for: blobName).path) }

    public func delete(_ blobNames: [String]) {
        for name in blobNames { try? fm.removeItem(at: url(for: name)) }
    }
}
