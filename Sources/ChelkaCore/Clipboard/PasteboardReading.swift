import AppKit

public struct PasteboardSnapshot: Equatable {
    public let changeCount: Int
    public let types: [String]
    public let text: String?
    public let imageData: Data?
    public let imageExtension: String?
    public let fileURLs: [URL]
    public let sourceBundleID: String?

    public init(changeCount: Int, types: [String], text: String?, imageData: Data?,
                imageExtension: String?, fileURLs: [URL], sourceBundleID: String?) {
        self.changeCount = changeCount
        self.types = types
        self.text = text
        self.imageData = imageData
        self.imageExtension = imageExtension
        self.fileURLs = fileURLs
        self.sourceBundleID = sourceBundleID
    }

    public var byteCount: Int {
        imageData?.count ?? text.map { $0.utf8.count } ?? 0
    }
}

public protocol PasteboardReading {
    func snapshot() -> PasteboardSnapshot
}

public struct SystemPasteboard: PasteboardReading {
    public init() {}

    public func snapshot() -> PasteboardSnapshot {
        let pb = NSPasteboard.general
        let types = (pb.types ?? []).map(\.rawValue)

        var imageData: Data?
        var imageExt: String?
        for (type, ext) in [(NSPasteboard.PasteboardType.png, "png"),
                            (NSPasteboard.PasteboardType.tiff, "tiff")] {
            if let d = pb.data(forType: type) { imageData = d; imageExt = ext; break }
        }

        let urls = (pb.readObjects(forClasses: [NSURL.self],
                                   options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []

        return PasteboardSnapshot(
            changeCount: pb.changeCount,
            types: types,
            text: pb.string(forType: .string),
            imageData: imageData,
            imageExtension: imageExt,
            fileURLs: urls,
            sourceBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }
}
