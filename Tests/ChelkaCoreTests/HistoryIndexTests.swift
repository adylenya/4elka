import Testing
import Foundation
@testable import ChelkaCore

private func root() -> URL {
    let u = FileManager.default.temporaryDirectory
        .appendingPathComponent("chelka-idx-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

@Test func roundTripsHistoryThroughDisk() throws {
    let dir = root()
    let blobs = BlobStore(root: dir.appendingPathComponent("blobs"))
    let index = HistoryIndex(fileURL: dir.appendingPathComponent("index.json"), blobs: blobs)

    let item = ClipItem(id: UUID(), kind: .text("привет"), sourceAppBundleID: "com.apple.Safari",
                        createdAt: Date(timeIntervalSince1970: 1000),
                        contentHash: "abc", isPinned: true)
    try index.save(HistoryStore(items: [item]))

    let loaded = index.load()
    #expect(loaded.items.count == 1)
    #expect(loaded.items.first?.kind == .text("привет"))
    #expect(loaded.items.first?.isPinned == true)
}

@Test func dropsItemsWhoseBlobDisappeared() throws {
    let dir = root()
    let blobs = BlobStore(root: dir.appendingPathComponent("blobs"))
    let index = HistoryIndex(fileURL: dir.appendingPathComponent("index.json"), blobs: blobs)

    let name = try blobs.write(Data([1]), extension: "png")
    let alive = ClipItem(id: UUID(),
                         kind: .image(.init(blobName: name, byteCount: 1, pixelSize: .init(width: 1, height: 1))),
                         sourceAppBundleID: nil, createdAt: Date(), contentHash: "a", isPinned: false)
    let orphan = ClipItem(id: UUID(),
                          kind: .image(.init(blobName: "пропал.png", byteCount: 1, pixelSize: .init(width: 1, height: 1))),
                          sourceAppBundleID: nil, createdAt: Date(), contentHash: "b", isPinned: false)
    try index.save(HistoryStore(items: [alive, orphan]))

    let loaded = index.load()
    #expect(loaded.items.count == 1)
    #expect(loaded.items.first?.blobName == name)
}

@Test func loadReturnsEmptyStoreWhenIndexIsMissing() {
    let dir = root()
    let index = HistoryIndex(fileURL: dir.appendingPathComponent("нет.json"),
                            blobs: BlobStore(root: dir))
    #expect(index.load().items.isEmpty)
}

@Test func loadReturnsEmptyStoreOnCorruptIndex() throws {
    let dir = root()
    let file = dir.appendingPathComponent("index.json")
    try Data("это не json".utf8).write(to: file)
    #expect(HistoryIndex(fileURL: file, blobs: BlobStore(root: dir)).load().items.isEmpty)
}
