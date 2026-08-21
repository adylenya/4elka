import AppKit
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

/// Координатор со своим каталогом перетаскивания: файлы жеста не должны
/// сыпаться в общий `AppPaths.dragTemp`, где их увидят другие тесты.
@MainActor
private func makeDragCoordinator() -> (ClipboardCoordinator, BlobStore, URL) {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("chelka-drag-\(UUID().uuidString)")
    let blobs = BlobStore(root: dir.appendingPathComponent("blobs"))
    let index = HistoryIndex(fileURL: dir.appendingPathComponent("index.json"), blobs: blobs)
    let capture = ClipboardCapture(rules: IgnoreRules(ownBundleID: "own"), blobs: blobs)
    let dragRoot = dir.appendingPathComponent("drag")
    let coordinator = ClipboardCoordinator(capture: capture, index: index, blobs: blobs,
                                           activity: ActivityCenter(panelState: { .hidden }),
                                           dragRoot: dragRoot)
    return (coordinator, blobs, dragRoot)
}

/// Один и тот же каталог на диске для проверок «пережило ли перезапуск»:
/// `launch()` создаёт координатор заново, как при новом запуске приложения.
@MainActor
private final class Restartable {
    let blobs: BlobStore
    let index: HistoryIndex
    private let capture: ClipboardCapture

    init() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("chelka-restart-\(UUID().uuidString)")
        blobs = BlobStore(root: dir.appendingPathComponent("blobs"))
        index = HistoryIndex(fileURL: dir.appendingPathComponent("index.json"), blobs: blobs)
        capture = ClipboardCapture(rules: IgnoreRules(ownBundleID: "own"), blobs: blobs)
    }

    func launch() -> ClipboardCoordinator {
        ClipboardCoordinator(capture: capture, index: index, blobs: blobs,
                             activity: ActivityCenter(panelState: { .hidden }))
    }
}

private func snap(_ text: String, app: String? = "com.apple.Safari") -> PasteboardSnapshot {
    PasteboardSnapshot(changeCount: 1, types: ["public.utf8-plain-text"], text: text,
                       imageData: nil, imageExtension: nil, fileURLs: [], sourceBundleID: app)
}

private func imageSnap(_ byte: UInt8) -> PasteboardSnapshot {
    PasteboardSnapshot(changeCount: 1, types: ["public.png"], text: nil,
                       imageData: Data([0x89, 0x50, 0x4E, 0x47, byte]), imageExtension: "png",
                       fileURLs: [], sourceBundleID: "com.apple.Safari")
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

/// Файл картинки нельзя удалять раньше, чем на диск лёг индекс без ссылок на
/// него. Повторное копирование той же картинки — это дедуп: пишется новый блоб,
/// прежний становится вытесненным, а запись индекса попадает в окно задержки.
/// Удалив файл сразу, мы оставляли на диске индекс со ссылкой на исчезнувший
/// файл — а такие элементы `load()` отбрасывает, и вся картинка пропадала.
@Test @MainActor func imageSurvivesRestartWhenTheSameImageIsCopiedTwiceInARow() {
    let disk = Restartable()
    let first = disk.launch()
    first.handle(imageSnap(1), now: Date())
    first.handle(imageSnap(1), now: Date())
    #expect(first.history.items.count == 1)

    let second = disk.launch()

    #expect(second.history.items.count == 1)
    let name = second.history.items.first?.blobName ?? ""
    #expect(disk.blobs.exists(name))
}

/// Удаление — это воля человека, и она обязана попадать на диск сразу. Пока
/// удаление жило в окне задержки, скопированный пароль, стёртый из панели,
/// возвращался в историю после перезапуска: то есть удаление личного просто
/// не выполнялось.
@Test @MainActor func removedItemDoesNotComeBackAfterRestart() {
    let disk = Restartable()
    let first = disk.launch()
    first.handle(snap("пароль"), now: Date())
    let id = first.history.items[0].id

    first.remove(id)

    #expect(disk.launch().history.items.isEmpty)
}

/// Закрепление — тоже воля человека, и его тоже нельзя оставлять в памяти.
@Test @MainActor func pinSurvivesRestart() {
    let disk = Restartable()
    let first = disk.launch()
    first.handle(snap("нужное"), now: Date())

    first.pin(first.history.items[0].id)

    #expect(disk.launch().history.items.first?.isPinned == true)
}

/// Второе копирование подряд попадает в окно задержки и живёт только в памяти.
/// Выход из приложения обязан сбросить индекс на диск, иначе оно пропадает.
@Test @MainActor func secondCopyInARowSurvivesTerminationBecauseIndexIsFlushed() {
    let disk = Restartable()
    let first = disk.launch()
    first.handle(snap("раз"), now: Date())
    first.handle(snap("два"), now: Date())

    first.flush()

    #expect(disk.launch().history.items.map(\.kind) == [.text("два"), .text("раз")])
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

// MARK: - Имена и подготовка файлов для перетаскивания

@Test func dragNameForImageUsesTimestamp() {
    let item = ClipItem(id: UUID(), kind: .image(.init(blobName: "a.png", byteCount: 1, pixelSize: .zero)),
                        sourceAppBundleID: nil,
                        createdAt: Date(timeIntervalSince1970: 0), contentHash: "h", isPinned: false)
    #expect(ClipboardCoordinator.dragName(for: item).hasPrefix("Снимок 1970-01-01"))
}

@Test func dragNameForLongTextIsTrimmed() {
    let item = ClipItem(id: UUID(), kind: .text(String(repeating: "я", count: 100)),
                        sourceAppBundleID: nil, createdAt: Date(), contentHash: "h", isPinned: false)
    #expect(ClipboardCoordinator.dragName(for: item).count == 40)
}

@Test @MainActor func materializeForDragWritesTextAsFileUnderItsName() throws {
    let (c, _, _) = makeDragCoordinator()
    c.handle(snap("первая строка\nвторая"), now: Date())
    let ids = c.history.items.map(\.id)

    let urls = c.materializeForDrag(ids)

    #expect(urls.count == 1)
    #expect(urls.first?.lastPathComponent == "первая строка.txt")
    #expect(try String(contentsOf: urls[0], encoding: .utf8) == "первая строка\nвторая")
}

/// Контракт задачи 4: пропавший с диска блоб выбрасывает из жеста один элемент,
/// а не ломает перетаскивание целиком.
@Test @MainActor func materializeForDragDropsItemWhoseBlobVanished() {
    let (c, blobs, _) = makeDragCoordinator()
    c.handle(imageSnap(1), now: Date())
    c.handle(imageSnap(2), now: Date())
    let items = c.history.items
    #expect(items.count == 2)
    blobs.delete([items[0].blobName ?? ""])

    let urls = c.materializeForDrag(items.map(\.id))

    #expect(urls.count == 1)
    #expect(FileManager.default.fileExists(atPath: urls[0].path))
}

@Test @MainActor func materializeForDragSweepsStaleFilesOfPreviousGestures() throws {
    let (c, _, dragRoot) = makeDragCoordinator()
    try FileManager.default.createDirectory(at: dragRoot, withIntermediateDirectories: true)
    let stale = dragRoot.appendingPathComponent("прошлый жест.txt")
    try Data("x".utf8).write(to: stale)
    try FileManager.default.setAttributes(
        [.modificationDate: Date(timeIntervalSinceNow: -Config.Drag.tempLifetime - 60)],
        ofItemAtPath: stale.path)

    c.handle(snap("свежий"), now: Date())
    _ = c.materializeForDrag(c.history.items.map(\.id))

    #expect(FileManager.default.fileExists(atPath: stale.path) == false)
}

// MARK: - Групповые операции над выделенным

@Test @MainActor func removingSeveralAtOnceDropsThemAllAndTheirBlobs() {
    let (c, blobs, _) = makeDragCoordinator()
    c.handle(imageSnap(1), now: Date())
    c.handle(imageSnap(2), now: Date())
    let items = c.history.items
    let names = items.compactMap(\.blobName)

    c.remove(items.map(\.id))

    #expect(c.history.items.isEmpty)
    #expect(names.count == 2)
    #expect(names.allSatisfy { blobs.exists($0) == false })
}

@Test @MainActor func togglePinPinsWholeSelectionAndThenReleasesIt() {
    let (c, _, _) = makeDragCoordinator()
    c.handle(snap("один"), now: Date())
    c.handle(snap("два"), now: Date())
    let ids = c.history.items.map(\.id)

    c.togglePin(ids)
    #expect(c.history.items.allSatisfy { $0.isPinned })

    c.togglePin(ids)
    #expect(c.history.items.allSatisfy { !$0.isPinned })
}

/// Один незакреплённый в выделении означает «закрепить всё», а не «переключить
/// каждый по-своему»: иначе одна клавиша давала бы разнобой внутри выделения.
@Test @MainActor func togglePinOnMixedSelectionPinsEverything() {
    let (c, _, _) = makeDragCoordinator()
    c.handle(snap("один"), now: Date())
    c.handle(snap("два"), now: Date())
    let ids = c.history.items.map(\.id)
    c.pin(ids[0])

    c.togglePin(ids)

    #expect(c.history.items.allSatisfy { $0.isPinned })
}

/// Системный буфер в тестах не трогаем — пишем в свой именованный.
/// Возвращённый номер записи обязан совпадать с номером буфера: по нему
/// наблюдатель отличает нашу запись от чужого копирования.
@Test func copyWritesTextToGivenPasteboardAndReportsItsChangeCount() {
    let pb = NSPasteboard(name: NSPasteboard.Name("com.adylenya.4elka.tests"))
    let item = ClipItem(id: UUID(), kind: .text("отдай меня"), sourceAppBundleID: nil,
                        createdAt: Date(), contentHash: "h", isPinned: false)

    let reported = ClipboardCoordinator.write(
        item, to: pb, blobs: BlobStore(root: FileManager.default.temporaryDirectory))

    #expect(pb.string(forType: .string) == "отдай меня")
    #expect(reported == pb.changeCount)
}

/// Пропавший блоб оставляет буфер пустым, а не с прошлым содержимым: вставить
/// вместо картинки чужой старый текст было бы хуже, чем не вставить ничего.
@Test func copyOfVanishedImageLeavesPasteboardEmpty() {
    let pb = NSPasteboard(name: NSPasteboard.Name("com.adylenya.4elka.tests.gone"))
    pb.clearContents()
    pb.setString("прошлое", forType: .string)
    let item = ClipItem(id: UUID(),
                        kind: .image(.init(blobName: "нет-такого.png", byteCount: 1, pixelSize: .zero)),
                        sourceAppBundleID: nil, createdAt: Date(), contentHash: "h", isPinned: false)

    ClipboardCoordinator.write(item, to: pb,
                               blobs: BlobStore(root: FileManager.default.temporaryDirectory))

    #expect(pb.string(forType: .string) == nil)
}

@Test func copyWritesFileURLsToGivenPasteboard() {
    let pb = NSPasteboard(name: NSPasteboard.Name("com.adylenya.4elka.tests.files"))
    let url = URL(fileURLWithPath: "/tmp/чек.pdf")
    let item = ClipItem(id: UUID(), kind: .files([url]), sourceAppBundleID: nil,
                        createdAt: Date(), contentHash: "h", isPinned: false)

    ClipboardCoordinator.write(item, to: pb, blobs: BlobStore(root: FileManager.default.temporaryDirectory))

    let read = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
    #expect(read == [url])
}
