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

/// Недописанный файл — обрезанный ровно посередине — это то, как выглядит любой
/// обрыв записи: кончилось место, паника ядра. Подменять его пустой историей
/// нельзя: первая же запись затрёт файл, и пятьдесят записей исчезнут навсегда.
/// Он обязан лечь в сторону целиком, до последнего байта.
@Test func truncatedIndexIsSetAsideWithItsBytesIntact() throws {
    let dir = root()
    let file = dir.appendingPathComponent("index.json")
    let index = HistoryIndex(fileURL: file, blobs: BlobStore(root: dir))
    let items = (0..<50).map { i in
        ClipItem(id: UUID(), kind: .text("запись \(i)"), sourceAppBundleID: nil,
                 createdAt: Date(timeIntervalSince1970: 1000), contentHash: "h\(i)",
                 isPinned: i == 7)
    }
    try index.save(HistoryStore(items: items))
    let whole = try Data(contentsOf: file)
    let half = whole.prefix(whole.count / 2)
    try Data(half).write(to: file)

    #expect(index.load().items.isEmpty)

    #expect(FileManager.default.fileExists(atPath: file.path) == false)
    let setAside = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        .filter { $0.hasPrefix("index.json.broken-") }
    #expect(setAside.count == 1)
    let kept = try #require(setAside.first)
    #expect(try Data(contentsOf: dir.appendingPathComponent(kept)) == Data(half))
}

/// Тот же путь ждёт будущую смену схемы `ClipItem`: разбор упадёт, и без
/// откладывания в сторону вся история пропала бы при обновлении приложения.
@Test func indexOfForeignSchemaIsSetAsideNotDropped() throws {
    let dir = root()
    let file = dir.appendingPathComponent("index.json")
    try Data(#"[{"поле-из-будущего": 1}]"#.utf8).write(to: file)

    #expect(HistoryIndex(fileURL: file, blobs: BlobStore(root: dir)).load().items.isEmpty)

    #expect(FileManager.default.fileExists(atPath: file.path) == false)
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path)
        .contains { $0.hasPrefix("index.json.broken-") })
}

/// Имя отложенного файла — чистая функция: исходное имя остаётся целиком, чтобы
/// человек нашёл файл глазами, а метка времени говорит, когда индекс сломался.
@Test func brokenNameKeepsOriginalNameAndCarriesTimestamp() {
    let name = HistoryIndex.brokenName(for: "index.json", at: Date(timeIntervalSince1970: 0))
    #expect(name.hasPrefix("index.json.broken-"))
    #expect(name == "index.json.broken-1970-01-01-060000")
}

