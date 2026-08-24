import Testing
import Foundation
@testable import ChelkaCore

/// Подготовка выделенного к перетаскиванию наружу. Отдельный файл, а не общий
/// с `ClipboardCoordinatorTests`: там свои темы (история, буфер, группы), а
/// здесь одна — что именно уезжает в жест.

/// Координатор со своим каталогом жеста: файлы не должны сыпаться в общий
/// `AppPaths.dragTemp`, где их увидят и уборщик, и соседний тест.
@MainActor
private func makeCoordinator() -> (ClipboardCoordinator, URL) {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("chelka-drag-out-\(UUID().uuidString)")
    let blobs = BlobStore(root: dir.appendingPathComponent("blobs"))
    let index = HistoryIndex(fileURL: dir.appendingPathComponent("index.json"), blobs: blobs)
    let capture = ClipboardCapture(rules: IgnoreRules(ownBundleID: "own"), blobs: blobs)
    let coordinator = ClipboardCoordinator(capture: capture, index: index, blobs: blobs,
                                           activity: ActivityCenter(panelState: { .hidden }),
                                           dragRoot: dir.appendingPathComponent("drag"))
    return (coordinator, dir)
}

private func filesSnapshot(_ urls: [URL]) -> PasteboardSnapshot {
    PasteboardSnapshot(changeCount: 1, types: ["public.file-url"], text: nil,
                       imageData: nil, imageExtension: nil, fileURLs: urls,
                       sourceBundleID: "com.apple.finder")
}

private func makeFiles(_ names: [String], in dir: URL) throws -> [URL] {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return try names.map { name in
        let url = dir.appendingPathComponent(name)
        try Data("x".utf8).write(to: url)
        return url
    }
}

/// В Finder выделено три файла и нажат `⌘C` — это ОДНА запись истории с тремя
/// путями. В жест обязаны уехать все три: раньше уезжал только первый, и два
/// файла пропадали молча.
@Test @MainActor func dragOfMultiFileItemCarriesEveryFile() throws {
    let (c, dir) = makeCoordinator()
    let files = try makeFiles(["а.pdf", "б.pdf", "в.pdf"], in: dir.appendingPathComponent("src"))
    c.handle(filesSnapshot(files), now: Date())

    let urls = c.materializeForDrag(c.history.items.map(\.id))

    #expect(urls == files)
}

/// Оригинал удалили после копирования — мёртвый путь в жесте уносит элемент в
/// никуда. Контракт «ошибка по каждому элементу отдельно» должен работать и
/// для вида «файлы»: пропавшие отбрасываются, целые едут.
@Test @MainActor func dragOfMultiFileItemDropsVanishedPaths() throws {
    let (c, dir) = makeCoordinator()
    let files = try makeFiles(["мёртвый.pdf", "живой.pdf"], in: dir.appendingPathComponent("src"))
    c.handle(filesSnapshot(files), now: Date())
    try FileManager.default.removeItem(at: files[0])

    let urls = c.materializeForDrag(c.history.items.map(\.id))

    #expect(urls == [files[1]])
}

/// Все пути мертвы — жест не получает ничего, а не мёртвый путь.
@Test @MainActor func dragOfItemWhoseFilesAllVanishedGivesNothing() throws {
    let (c, dir) = makeCoordinator()
    let files = try makeFiles(["ушёл.pdf"], in: dir.appendingPathComponent("src"))
    c.handle(filesSnapshot(files), now: Date())
    try FileManager.default.removeItem(at: files[0])

    #expect(c.materializeForDrag(c.history.items.map(\.id)).isEmpty)
}
