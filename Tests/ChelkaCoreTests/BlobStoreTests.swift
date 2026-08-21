import Testing
import Foundation
@testable import ChelkaCore

private func root() -> URL {
    let u = FileManager.default.temporaryDirectory
        .appendingPathComponent("chelka-blob-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

@Test func writesBlobAndReadsItBack() throws {
    let store = BlobStore(root: root().appendingPathComponent("blobs"))
    let name = try store.write(Data([1, 2, 3]), extension: "png")
    #expect(name.hasSuffix(".png"))
    #expect(store.exists(name))
    #expect(try Data(contentsOf: store.url(for: name)) == Data([1, 2, 3]))
}

@Test func deletesBlobs() throws {
    let store = BlobStore(root: root())
    let name = try store.write(Data([9]), extension: "png")
    store.delete([name])
    #expect(!store.exists(name))
}

@Test func deletingMissingBlobDoesNotThrow() {
    BlobStore(root: root()).delete(["нет-такого.png"])
}
