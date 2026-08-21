import Testing
import Foundation
@testable import ChelkaCore

private func text(_ s: String, pinned: Bool = false, at: Date = Date()) -> ClipItem {
    ClipItem(id: UUID(), kind: .text(s), sourceAppBundleID: nil,
             createdAt: at, contentHash: Hashing.sha256(Data(s.utf8)), isPinned: pinned)
}

private func image(_ name: String) -> ClipItem {
    ClipItem(id: UUID(),
             kind: .image(.init(blobName: name, byteCount: 10, pixelSize: .init(width: 2, height: 2))),
             sourceAppBundleID: nil, createdAt: Date(),
             contentHash: Hashing.sha256(Data(name.utf8)), isPinned: false)
}

@Test func insertingDoesNotMutateOriginal() {
    let before = HistoryStore(items: [text("a")])
    _ = before.inserting(text("b"))
    #expect(before.items.count == 1)
}

@Test func newestItemComesFirst() {
    let s = HistoryStore().inserting(text("a")).inserting(text("b"))
    #expect(s.items.first?.kind == .text("b"))
}

@Test func duplicateRaisesExistingInsteadOfAddingSecond() {
    let s = HistoryStore().inserting(text("a")).inserting(text("b")).inserting(text("a"))
    #expect(s.items.count == 2)
    #expect(s.items.first?.kind == .text("a"))
}

@Test func textQuotaEvictsOldest() {
    var s = HistoryStore()
    for i in 0..<(Config.History.textLimit + 5) { s = s.inserting(text("t\(i)")) }
    #expect(s.items.count == Config.History.textLimit)
    #expect(!s.items.contains { $0.kind == .text("t0") })
}

@Test func quotasAreCountedPerKindNotTogether() {
    var s = HistoryStore()
    for i in 0..<Config.History.textLimit { s = s.inserting(text("t\(i)")) }
    s = s.inserting(image("one.png"))
    #expect(s.items.contains { $0.isImage })
    #expect(s.items.filter { !$0.isImage }.count == Config.History.textLimit)
}

@Test func pinnedItemsSurviveEviction() {
    var s = HistoryStore().inserting(text("важное", pinned: true))
    for i in 0..<(Config.History.textLimit + 10) { s = s.inserting(text("t\(i)")) }
    #expect(s.items.contains { $0.kind == .text("важное") })
}

@Test func pinningReturnsNewStoreWithFlagSet() {
    let item = text("a")
    let s = HistoryStore(items: [item]).pinning(item.id)
    #expect(s.items.first?.isPinned == true)
    #expect(HistoryStore(items: [item]).items.first?.isPinned == false)
}

@Test func removingDropsItem() {
    let item = text("a")
    #expect(HistoryStore(items: [item]).removing(item.id).items.isEmpty)
}

@Test func reportsBlobsThatFellOutSoTheyCanBeDeleted() {
    let kept = image("keep.png")
    let dropped = image("drop.png")
    let before = HistoryStore(items: [kept, dropped])
    let after = before.removing(dropped.id)
    #expect(after.evictedBlobNames(comparedTo: before) == ["drop.png"])
}
