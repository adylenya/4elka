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

private func permissions(_ url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
}

/// История лежит открытым текстом, и в ней оказывается всё скопированное —
/// включая то, что копировать не стоило. Читать этот файл может только владелец.
@Test func writtenFileIsReadableOnlyByItsOwner() throws {
    let file = root().appendingPathComponent("тайна.json")
    try AtomicFile.write(Data("секрет".utf8), to: file)
    #expect(try permissions(file) == 0o600)
}

/// Перезапись идёт через подмену файла, и права нового файла не должны
/// наследоваться от прежнего — иначе однажды созданный файл с правами 0644
/// оставался бы открытым всем навсегда.
@Test func overwritingKeepsTheFilePrivate() throws {
    let file = root().appendingPathComponent("тайна.json")
    try Data("первое".utf8).write(to: file)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)

    try AtomicFile.write(Data("второе".utf8), to: file)

    #expect(try permissions(file) == 0o600)
    #expect(try Data(contentsOf: file) == Data("второе".utf8))
}

@Test func blobIsReadableOnlyByItsOwner() throws {
    let store = BlobStore(root: root().appendingPathComponent("blobs"))
    let name = try store.write(Data([1, 2, 3]), extension: "png")
    #expect(try permissions(store.url(for: name)) == 0o600)
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
