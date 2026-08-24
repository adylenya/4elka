import Testing
import Foundation
@testable import ChelkaCore

private func dir() -> URL {
    let u = FileManager.default.temporaryDirectory
        .appendingPathComponent("chelka-atomic-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

private func permissions(_ url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return try #require(attributes[.posixPermissions] as? NSNumber).intValue
}

/// Временных огрызков после удачной записи оставаться не должно: подчищать их
/// больше некому, и на тысячах записей это тихая утечка места.
@Test func atomicWriteLeavesNoTemporaryLeftovers() throws {
    let root = dir()
    let file = root.appendingPathComponent("index.json")
    try AtomicFile.write(Data("привет".utf8), to: file)
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path)
        .filter { $0.hasSuffix(".tmp") }
    #expect(leftovers.isEmpty)
    #expect(try Data(contentsOf: file) == Data("привет".utf8))
}

/// Файл со сброшенными на носитель байтами обязан читаться целиком сразу после
/// возврата из записи. Сам `fsync` изнутри процесса не проверить — потеря
/// питания в тест не входит, — но обрыв на этой дороге виден именно тут:
/// недописанный файл разобрался бы не полностью.
@Test func atomicWriteIsReadableInFullRightAfterReturning() throws {
    let file = dir().appendingPathComponent("index.json")
    let payload = Data((0..<200_000).map { UInt8($0 % 251) })
    try AtomicFile.write(payload, to: file)
    #expect(try Data(contentsOf: file) == payload)
}

@Test func atomicWriteHandlesEmptyPayload() throws {
    let file = dir().appendingPathComponent("пусто.json")
    try AtomicFile.write(Data(), to: file)
    #expect(try Data(contentsOf: file).isEmpty)
}

/// Права ставятся и на подмене: однажды созданный файл с правами 0644 иначе
/// остался бы читаемым всем, кто есть на машине, навсегда.
@Test func atomicWriteTightensPermissionsOfAnAlreadyOpenFile() throws {
    let file = dir().appendingPathComponent("index.json")
    try Data("старое".utf8).write(to: file)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)

    try AtomicFile.write(Data("новое".utf8), to: file)

    #expect(try permissions(file) == 0o600)
    #expect(try Data(contentsOf: file) == Data("новое".utf8))
}

/// Провал записи не оставляет ни огрызка, ни половины итогового файла: старое
/// содержимое остаётся на месте целиком.
@Test func failedAtomicWriteKeepsPreviousContentIntact() throws {
    let root = dir()
    let file = root.appendingPathComponent("index.json")
    try AtomicFile.write(Data("важное".utf8), to: file)
    // Каталог без права записи: временный файл создать не выйдет.
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700],
                                                   ofItemAtPath: root.path) }

    #expect(throws: (any Error).self) {
        try AtomicFile.write(Data("новое".utf8), to: file)
    }
    #expect(try Data(contentsOf: file) == Data("важное".utf8))
}
