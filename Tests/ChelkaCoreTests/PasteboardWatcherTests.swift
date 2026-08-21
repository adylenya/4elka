import Testing
import Foundation
@testable import ChelkaCore

private func blobs() -> BlobStore {
    BlobStore(root: FileManager.default.temporaryDirectory
        .appendingPathComponent("chelka-cap-\(UUID().uuidString)"))
}
private let rules = IgnoreRules(ownBundleID: "com.adylenya.4elka")
private let now = Date(timeIntervalSince1970: 500)

private func snap(types: [String], text: String? = nil, image: Data? = nil,
                  ext: String? = nil, urls: [URL] = [], app: String? = nil) -> PasteboardSnapshot {
    PasteboardSnapshot(changeCount: 1, types: types, text: text, imageData: image,
                       imageExtension: ext, fileURLs: urls, sourceBundleID: app)
}

@Test func capturesPlainText() {
    let r = ClipboardCapture(rules: rules, blobs: blobs())
        .capture(snap(types: ["public.utf8-plain-text"], text: "привет"),
                 into: HistoryStore(), now: now)
    #expect(r.inserted?.kind == .text("привет"))
    #expect(r.store.items.count == 1)
}

@Test func capturesImageAndWritesBlob() {
    let store = blobs()
    let r = ClipboardCapture(rules: rules, blobs: store)
        .capture(snap(types: ["public.png"], image: Data([0x89, 0x50]), ext: "png"),
                 into: HistoryStore(), now: now)
    let name = try! #require(r.inserted?.blobName)
    #expect(store.exists(name))
}

@Test func capturesFileURLs() {
    let url = URL(fileURLWithPath: "/tmp/файл.pdf")
    let r = ClipboardCapture(rules: rules, blobs: blobs())
        .capture(snap(types: ["public.file-url"], urls: [url]), into: HistoryStore(), now: now)
    #expect(r.inserted?.kind == .files([url]))
}

@Test func obeysIgnoreRules() {
    let r = ClipboardCapture(rules: rules, blobs: blobs())
        .capture(snap(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"],
                      text: "пароль"), into: HistoryStore(), now: now)
    #expect(r.inserted == nil)
    #expect(r.store.items.isEmpty)
}

@Test func ignoresOwnCopiesSoCardDoesNotEcho() {
    let r = ClipboardCapture(rules: rules, blobs: blobs())
        .capture(snap(types: ["public.utf8-plain-text"], text: "эхо", app: "com.adylenya.4elka"),
                 into: HistoryStore(), now: now)
    #expect(r.inserted == nil)
}

@Test func emptySnapshotProducesNothing() {
    let r = ClipboardCapture(rules: rules, blobs: blobs())
        .capture(snap(types: []), into: HistoryStore(), now: now)
    #expect(r.inserted == nil)
}

@Test func reportsEvictedBlobsSoFilesCanBeDeleted() {
    let store = blobs()
    let capture = ClipboardCapture(rules: rules, blobs: store)
    var history = HistoryStore()
    var firstBlob: String?
    for i in 0..<(Config.History.imageLimit + 1) {
        let r = capture.capture(snap(types: ["public.png"], image: Data([UInt8(i % 250), 0x50]), ext: "png"),
                                into: history, now: now)
        history = r.store
        if i == 0 { firstBlob = r.inserted?.blobName }
        if i == Config.History.imageLimit { #expect(r.evictedBlobNames == [firstBlob!]) }
    }
}
