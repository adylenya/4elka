import Testing
import Foundation
@testable import ChelkaCore

@MainActor
private func makeCoordinator(panel: @escaping () -> PanelState = { .hidden })
    -> (ClipboardCoordinator, ActivityCenter) {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("chelka-coord-\(UUID().uuidString)")
    let blobs = BlobStore(root: dir.appendingPathComponent("blobs"))
    let index = HistoryIndex(fileURL: dir.appendingPathComponent("index.json"), blobs: blobs)
    let capture = ClipboardCapture(rules: IgnoreRules(ownBundleID: "com.adylenya.4elka"), blobs: blobs)
    let center = ActivityCenter(panelState: panel)
    return (ClipboardCoordinator(capture: capture, index: index, blobs: blobs, activity: center), center)
}

private func snap(_ text: String, app: String? = "com.apple.Safari") -> PasteboardSnapshot {
    PasteboardSnapshot(changeCount: 1, types: ["public.utf8-plain-text"], text: text,
                       imageData: nil, imageExtension: nil, fileURLs: [], sourceBundleID: app)
}

@Test @MainActor func storesItemAndRaisesCard() {
    let (c, center) = makeCoordinator()
    c.handle(snap("привет"), now: Date())
    #expect(c.history.items.count == 1)
    #expect(center.queue.current?.kind == .clipboard)
    #expect(center.queue.current?.title == "привет")
}

@Test @MainActor func ignoredCopyRaisesNoCard() {
    let (c, center) = makeCoordinator()
    c.handle(snap("эхо", app: "com.adylenya.4elka"), now: Date())
    #expect(c.history.items.isEmpty)
    #expect(center.queue.current == nil)
}

@Test @MainActor func noCardWhilePanelExpanded() {
    let (c, center) = makeCoordinator(panel: { .expanded })
    c.handle(snap("привет"), now: Date())
    #expect(c.history.items.count == 1)
    #expect(center.queue.current == nil)
}

@Test @MainActor func cardDisappearsAfterDuration() {
    let (c, center) = makeCoordinator()
    let t = Date()
    c.handle(snap("привет"), now: t)
    center.tick(now: t.addingTimeInterval(Config.Activity.duration + 0.1))
    #expect(center.queue.current == nil)
}

@Test @MainActor func allThreeProducersShareOneQueueSoPrioritiesWork() {
    // Заряд важнее буфера: карточка буфера не должна перебивать карточку заряда.
    let (c, center) = makeCoordinator()
    let t = Date()
    center.submit(ActivityEvent(kind: .battery, title: "мало"), now: t)
    c.handle(snap("текст"), now: t.addingTimeInterval(0.5))
    #expect(center.queue.current?.kind == .battery)
}

@Test @MainActor func historySurvivesRestart() {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("chelka-restart-\(UUID().uuidString)")
    let blobs = BlobStore(root: dir.appendingPathComponent("blobs"))
    let index = HistoryIndex(fileURL: dir.appendingPathComponent("index.json"), blobs: blobs)
    let capture = ClipboardCapture(rules: IgnoreRules(ownBundleID: "own"), blobs: blobs)

    let first = ClipboardCoordinator(capture: capture, index: index, blobs: blobs,
                                     activity: ActivityCenter(panelState: { .hidden }))
    first.handle(snap("сохранись"), now: Date())

    let second = ClipboardCoordinator(capture: capture, index: index, blobs: blobs,
                                      activity: ActivityCenter(panelState: { .hidden }))
    #expect(second.history.items.first?.kind == .text("сохранись"))
}

@Test func cardTitleForImageMentionsScreenshotAndCarriesThumbnail() {
    let item = ClipItem(id: UUID(),
                        kind: .image(.init(blobName: "a.png", byteCount: 1,
                                          pixelSize: .init(width: 100, height: 50))),
                        sourceAppBundleID: nil, createdAt: Date(), contentHash: "h", isPinned: false)
    let e = ClipboardCoordinator.activityEvent(for: item)
    #expect(e.imageBlobName == "a.png")
    #expect(e.subtitle == "100 × 50")
}

@Test func cardTitleForFilesListsNames() {
    let item = ClipItem(id: UUID(),
                        kind: .files([URL(fileURLWithPath: "/tmp/a.pdf"),
                                      URL(fileURLWithPath: "/tmp/b.pdf")]),
                        sourceAppBundleID: nil, createdAt: Date(), contentHash: "h", isPinned: false)
    #expect(ClipboardCoordinator.activityEvent(for: item).title == "a.pdf, b.pdf")
}

@Test func cardTitleForMultilineTextTakesFirstLine() {
    let item = ClipItem(id: UUID(), kind: .text("первая\nвторая"), sourceAppBundleID: nil,
                        createdAt: Date(), contentHash: "h", isPinned: false)
    #expect(ClipboardCoordinator.activityEvent(for: item).title == "первая")
}
