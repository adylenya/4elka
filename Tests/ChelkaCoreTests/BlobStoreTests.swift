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

@Test func blobNameCannotEscapeItsDirectory() throws {
    // Имя приходит из индекса на диске. Битый индекс не должен давать возможность
    // удалить или прочитать что-то за пределами каталога блобов.
    let base = root()
    let outside = base.appendingPathComponent("посторонний.txt")
    try Data("не трогать".utf8).write(to: outside)

    let store = BlobStore(root: base.appendingPathComponent("blobs"))
    store.delete(["../посторонний.txt"])

    #expect(FileManager.default.fileExists(atPath: outside.path))
    // .path, не URL == : deletingLastPathComponent() всегда возвращает URL с
    // хвостовым "/" (директория), а appendingPathComponent — без него для
    // несуществующего пути, так что сравнение самих URL ложно не совпадёт
    // даже при корректном сдерживании — это артефакт Foundation, не баг.
    #expect(store.url(for: "../посторонний.txt").deletingLastPathComponent().path
            == base.appendingPathComponent("blobs").path)
}

@Test func failedWriteLeavesNoTemporaryFileBehind() throws {
    // Пишем «в каталог», которым на самом деле является обычный файл: запись обязана
    // упасть и не оставить огрызка рядом.
    let base = root()
    let blocker = base.appendingPathComponent("занято")
    try Data("я файл, а не каталог".utf8).write(to: blocker)

    #expect(throws: (any Error).self) {
        try AtomicFile.write(Data([1, 2, 3]), to: blocker.appendingPathComponent("внутри.json"))
    }

    let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? []
    #expect(!leftovers.contains { $0.hasSuffix(".tmp") })
}
