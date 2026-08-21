import Testing
import Foundation
@testable import ChelkaCore

private func makeTree() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("chelka-usage-\(UUID().uuidString)")
    let blobs = dir.appendingPathComponent("blobs")
    try FileManager.default.createDirectory(at: blobs, withIntermediateDirectories: true)
    try Data(repeating: 7, count: 100).write(to: dir.appendingPathComponent("index.json"))
    try Data(repeating: 7, count: 250).write(to: blobs.appendingPathComponent("a.png"))
    try Data(repeating: 7, count: 150).write(to: blobs.appendingPathComponent("b.png"))
    return dir
}

@Test func usageCountsFilesInsideDirectories() throws {
    let dir = try makeTree()
    let total = StorageUsage.bytes(of: [dir.appendingPathComponent("index.json"),
                                       dir.appendingPathComponent("blobs")])
    #expect(total == 500)
}

/// Отсутствующий путь — это ноль, а не отказ: до первого копирования ни
/// индекса, ни каталога блобов на диске нет.
@Test func usageOfMissingPathIsZero() {
    let missing = FileManager.default.temporaryDirectory
        .appendingPathComponent("нет-\(UUID().uuidString)")
    #expect(StorageUsage.bytes(of: [missing]) == 0)
    #expect(StorageUsage.bytes(of: []) == 0)
}

/// Один и тот же путь, переданный дважды, не должен удваивать размер.
@Test func usageDoesNotCountTheSameFileTwice() throws {
    let dir = try makeTree()
    let index = dir.appendingPathComponent("index.json")
    #expect(StorageUsage.bytes(of: [index, index]) == 100)
}

@Test func usageIsSpelledOutForHumans() {
    let zero = StorageUsage.formatted(0)
    let big = StorageUsage.formatted(5 * 1024 * 1024)
    #expect(!zero.isEmpty)
    #expect(!big.isEmpty)
    #expect(zero != big)
    #expect(big.contains { $0.isNumber })
}
