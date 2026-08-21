import Testing
import Foundation
@testable import ChelkaCore

private func t(_ s: String) -> ClipItem {
    ClipItem(id: UUID(), kind: .text(s), sourceAppBundleID: nil, createdAt: Date(),
             contentHash: s, isPinned: false)
}
private func img(_ n: String) -> ClipItem {
    ClipItem(id: UUID(), kind: .image(.init(blobName: n, byteCount: 1, pixelSize: .zero)),
             sourceAppBundleID: nil, createdAt: Date(), contentHash: n, isPinned: false)
}
private func f(_ p: String) -> ClipItem {
    ClipItem(id: UUID(), kind: .files([URL(fileURLWithPath: p)]), sourceAppBundleID: nil,
             createdAt: Date(), contentHash: p, isPinned: false)
}

@Test func emptyQueryKeepsEverythingOnAllTab() {
    #expect(HistorySearch.filter([t("а"), img("b.png")], tab: .all, query: "").count == 2)
}

@Test func imagesTabKeepsOnlyImages() {
    let r = HistorySearch.filter([t("а"), img("b.png"), f("/tmp/c")], tab: .images, query: "")
    #expect(r.count == 1)
    #expect(r.first?.isImage == true)
}

@Test func filesTabKeepsOnlyFiles() {
    #expect(HistorySearch.filter([t("а"), img("b.png"), f("/tmp/c")], tab: .files, query: "").count == 1)
}

@Test func searchIsCaseAndDiacriticInsensitive() {
    #expect(HistorySearch.filter([t("Привет Мир")], tab: .all, query: "привет мир").count == 1)
    #expect(HistorySearch.filter([t("ёлка")], tab: .all, query: "елка").count == 1)
}

@Test func searchMatchesFileNames() {
    #expect(HistorySearch.filter([f("/tmp/отчёт.pdf")], tab: .all, query: "отчет").count == 1)
}

@Test func searchDoesNotMatchImagesWithoutText() {
    #expect(HistorySearch.filter([img("b.png")], tab: .all, query: "b").isEmpty)
}
