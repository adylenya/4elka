import Testing
import Foundation
@testable import ChelkaCore

private func cleanerRoot() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("chelka-sweep-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func write(_ name: String, in root: URL, age: TimeInterval, now: Date) throws -> URL {
    let url = root.appendingPathComponent(name)
    try Data("x".utf8).write(to: url)
    try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age)],
                                          ofItemAtPath: url.path)
    return url
}

@Test func sweepRemovesStaleDragFilesAndKeepsFreshOnes() throws {
    let root = cleanerRoot()
    let now = Date()
    let old = try write("старый.txt", in: root, age: Config.Drag.tempLifetime + 60, now: now)
    let fresh = try write("свежий.txt", in: root, age: 1, now: now)

    DragTempCleaner(root: root).sweep(now: now)

    #expect(FileManager.default.fileExists(atPath: old.path) == false)
    #expect(FileManager.default.fileExists(atPath: fresh.path))
}

@Test func sweepOfMissingDirectoryIsHarmless() {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("chelka-sweep-нет-\(UUID().uuidString)")
    DragTempCleaner(root: root).sweep(now: Date())
    #expect(FileManager.default.fileExists(atPath: root.path) == false)
}
