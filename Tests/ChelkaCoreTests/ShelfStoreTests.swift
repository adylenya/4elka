import Testing
import Foundation
@testable import ChelkaCore

private let now = Date(timeIntervalSince1970: 100)
private func u(_ p: String) -> URL { URL(fileURLWithPath: p) }

/// Свой каталог на каждый тест: полка пишется в один файл, и общий каталог
/// сделал бы тесты зависимыми друг от друга.
private func shelfDir() -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("chelka-shelf-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func touch(_ url: URL) {
    try? Data("x".utf8).write(to: url)
}

// MARK: - Хранилище

@Test func addsFilesNewestFirst() {
    let s = ShelfStore().adding([u("/tmp/a.pdf")], now: now)
        .adding([u("/tmp/b.pdf")], now: now.addingTimeInterval(1))
    #expect(s.items.first?.name == "b.pdf")
    #expect(s.items.count == 2)
}

@Test func addingSameFileTwiceKeepsOneEntry() {
    let s = ShelfStore().adding([u("/tmp/a.pdf")], now: now)
        .adding([u("/tmp/a.pdf")], now: now.addingTimeInterval(1))
    #expect(s.items.count == 1)
}

@Test func addingIsImmutable() {
    let before = ShelfStore().adding([u("/tmp/a.pdf")], now: now)
    _ = before.adding([u("/tmp/b.pdf")], now: now)
    #expect(before.items.count == 1)
}

@Test func addsSeveralFilesAtOnce() {
    let s = ShelfStore().adding([u("/tmp/a.pdf"), u("/tmp/b.pdf")], now: now)
    #expect(s.items.count == 2)
}

@Test func removesById() {
    let s = ShelfStore().adding([u("/tmp/a.pdf")], now: now)
    let id = s.items[0].id
    #expect(s.removing(id).items.isEmpty)
}

@Test func prunesEntriesWhoseFileWasDeleted() {
    // Полка хранит ссылки, а не копии: файл могли удалить или переместить.
    let s = ShelfStore().adding([u("/tmp/жив.pdf"), u("/tmp/удалён.pdf")], now: now)
    let pruned = s.prunedOfMissingFiles { $0.lastPathComponent == "жив.pdf" }
    #expect(pruned.items.count == 1)
    #expect(pruned.items.first?.name == "жив.pdf")
}

@Test func airDropRefusesEmptySelection() {
    #expect(!AirDropSender.canSend([]))
}

@Test func airDropRefusesMissingFiles() {
    #expect(!AirDropSender.canSend([u("/tmp/нет-\(UUID().uuidString).pdf")]))
}

// MARK: - Имена и пути, которые ломают наивную реализацию

@Test func shelfKeepsCyrillicSpacesAndEmojiInNames() {
    let s = ShelfStore().adding([u("/tmp/Отчёт за август 🎉.pdf")], now: now)
    #expect(s.items.first?.name == "Отчёт за август 🎉.pdf")
}

@Test func shelfKeepsWholeNameOfFileWithoutExtension() {
    let s = ShelfStore().adding([u("/tmp/Makefile")], now: now)
    #expect(s.items.first?.name == "Makefile")
}

@Test func shelfKeepsVeryLongNameWhole() {
    let long = String(repeating: "имя", count: 80) + ".pdf"
    let s = ShelfStore().adding([u("/tmp/\(long)")], now: now)
    #expect(s.items.first?.name == long)
}

@Test func sameFileWrittenDifferentlyIsStillTheSameFile() {
    // Finder и наш собственный жест могут отдать один и тот же файл записанным
    // по-разному. Дубликата на полке от этого быть не должно.
    let s = ShelfStore().adding([u("/tmp/a.pdf")], now: now)
        .adding([u("/tmp/./a.pdf")], now: now.addingTimeInterval(1))
    #expect(s.items.count == 1)
}

@Test func addingSameFileTwiceInOneDropKeepsOneEntry() {
    let s = ShelfStore().adding([u("/tmp/a.pdf"), u("/tmp/a.pdf")], now: now)
    #expect(s.items.count == 1)
}

@Test func removingUnknownIdKeepsShelfIntact() {
    let s = ShelfStore().adding([u("/tmp/a.pdf")], now: now)
    #expect(s.removing(UUID()) == s)
}

@Test func removingIsImmutable() {
    let before = ShelfStore().adding([u("/tmp/a.pdf")], now: now)
    _ = before.removing(before.items[0].id)
    #expect(before.items.count == 1)
}

@Test func shelfIgnoresHistoryQuotas() {
    // Элементы полки живут до явного удаления: квота истории на файлы к ним
    // не относится.
    let urls = (0..<(Config.History.fileLimit + 10)).map { u("/tmp/f\($0).pdf") }
    #expect(ShelfStore().adding(urls, now: now).items.count == urls.count)
}

// MARK: - Полка на диске

@Test func shelfSurvivesRestart() {
    let dir = shelfDir()
    let index = ShelfIndex(fileURL: dir.appendingPathComponent("shelf.json"))
    let file = dir.appendingPathComponent("Отчёт за август 🎉.pdf")
    touch(file)
    try? index.save(ShelfStore().adding([file], now: now))
    #expect(index.load().items.first?.name == "Отчёт за август 🎉.pdf")
}

/// Битый файл полки не имеет права молча превратиться в пустую полку: первая же
/// запись затрёт его, и файлы, положенные руками, исчезнут навсегда. Он обязан
/// лечь в сторону — ровно как испорченный индекс истории.
@Test func brokenShelfFileIsSetAsideNotSilentlyDropped() throws {
    let dir = shelfDir()
    let url = dir.appendingPathComponent("shelf.json")
    try Data("{ это не json".utf8).write(to: url)

    #expect(ShelfIndex(fileURL: url).load().items.isEmpty)

    #expect(FileManager.default.fileExists(atPath: url.path) == false)
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path)
        .contains { $0.hasPrefix("shelf.json.broken-") })
}

/// Недописанный файл — обрезанный ровно посередине — это то, как выглядит обрыв
/// записи: кончилось место, потеря питания. Он обязан лечь в сторону целиком,
/// до последнего байта: только из этих байтов человек и достанет обратно имя
/// важного файла.
@Test func truncatedShelfFileIsSetAsideWithItsBytesIntact() throws {
    let dir = shelfDir()
    let file = dir.appendingPathComponent("shelf.json")
    let index = ShelfIndex(fileURL: file)
    let report = dir.appendingPathComponent("важный-отчёт.pdf")
    let other = dir.appendingPathComponent("прочее.pdf")
    touch(report)
    touch(other)
    // Важный файл брошен последним, значит лежит в начале файла и попадает
    // в уцелевшую половину — именно за ним человек и пойдёт в отложенное.
    try index.save(ShelfStore().adding([other], now: now)
        .adding([report], now: now.addingTimeInterval(1)))
    let whole = try Data(contentsOf: file)
    let half = whole.prefix(whole.count / 2)
    try Data(half).write(to: file)

    #expect(index.load().items.isEmpty)

    #expect(FileManager.default.fileExists(atPath: file.path) == false)
    let setAside = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        .filter { $0.hasPrefix("shelf.json.broken-") }
    #expect(setAside.count == 1)
    let kept = try #require(setAside.first)
    let bytes = try Data(contentsOf: dir.appendingPathComponent(kept))
    #expect(bytes == Data(half))
    // Имя файла, за которым человек и пойдёт в отложенное, обязано в нём быть.
    // В JSON оно лежит внутри `file://`-ссылки, то есть в процентной записи.
    let needle = report.lastPathComponent
        .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
    #expect(String(decoding: bytes, as: UTF8.self).contains(needle))
}

/// Тот же путь ждёт будущую смену схемы `ShelfItem`: разбор упадёт, и без
/// откладывания в сторону полка пропала бы при обновлении приложения.
@Test func shelfFileOfForeignSchemaIsSetAside() throws {
    let dir = shelfDir()
    let file = dir.appendingPathComponent("shelf.json")
    try Data(#"[{"поле-из-будущего": 1}]"#.utf8).write(to: file)

    #expect(ShelfIndex(fileURL: file).load().items.isEmpty)

    #expect(FileManager.default.fileExists(atPath: file.path) == false)
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path)
        .contains { $0.hasPrefix("shelf.json.broken-") })
}

@Test func missingShelfFileReadsAsEmptyShelf() {
    let url = shelfDir().appendingPathComponent("shelf.json")
    #expect(ShelfIndex(fileURL: url).load().items.isEmpty)
}

@Test func loadDropsEntryWhoseFileWasDeleted() {
    let dir = shelfDir()
    let index = ShelfIndex(fileURL: dir.appendingPathComponent("shelf.json"))
    let alive = dir.appendingPathComponent("жив.pdf")
    let doomed = dir.appendingPathComponent("удалён.pdf")
    touch(alive)
    touch(doomed)
    try? index.save(ShelfStore().adding([alive, doomed], now: now))
    try? FileManager.default.removeItem(at: doomed)
    let loaded = index.load()
    #expect(loaded.items.count == 1)
    #expect(loaded.items.first?.name == "жив.pdf")
}

@Test func directoryOnShelfIsNotMistakenForMissingFile() {
    let dir = shelfDir()
    let folder = dir.appendingPathComponent("папка", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let index = ShelfIndex(fileURL: dir.appendingPathComponent("shelf.json"))
    try? index.save(ShelfStore().adding([folder], now: now))
    #expect(index.load().items.count == 1)
}

// MARK: - Координатор полки

@Test @MainActor func shelfCoordinatorKeepsDroppedFilesAcrossRestart() async {
    let dir = shelfDir()
    let file = dir.appendingPathComponent("a.pdf")
    touch(file)
    let index = ShelfIndex(fileURL: dir.appendingPathComponent("shelf.json"))

    let coordinator = ShelfCoordinator(index: index)
    coordinator.add([file], now: now)
    #expect(coordinator.shelf.items.count == 1)

    let restarted = ShelfCoordinator(index: index)
    await restarted.load()
    #expect(restarted.shelf.items.first?.name == "a.pdf")
}

@Test @MainActor func shelfCoordinatorForgetsFileDeletedWhileAppWasClosed() async {
    let dir = shelfDir()
    let file = dir.appendingPathComponent("исчезнет.pdf")
    touch(file)
    let index = ShelfIndex(fileURL: dir.appendingPathComponent("shelf.json"))
    let coordinator = ShelfCoordinator(index: index)
    coordinator.add([file], now: now)
    try? FileManager.default.removeItem(at: file)

    let restarted = ShelfCoordinator(index: index)
    await restarted.load()
    #expect(restarted.shelf.items.isEmpty)
}

@Test @MainActor func shelfCoordinatorForgetsFileDeletedWhilePanelWasClosed() async {
    let dir = shelfDir()
    let file = dir.appendingPathComponent("исчезнет.pdf")
    touch(file)
    let coordinator = ShelfCoordinator(index: ShelfIndex(fileURL: dir.appendingPathComponent("shelf.json")))
    coordinator.add([file], now: now)
    try? FileManager.default.removeItem(at: file)
    await coordinator.pruneMissingFiles()
    #expect(coordinator.shelf.items.isEmpty)
}

@Test @MainActor func shelfCoordinatorRemovesSelectedItems() {
    let dir = shelfDir()
    let coordinator = ShelfCoordinator(index: ShelfIndex(fileURL: dir.appendingPathComponent("shelf.json")))
    coordinator.add([u("/tmp/a.pdf"), u("/tmp/b.pdf")], now: now)
    let ids = coordinator.shelf.items.map(\.id)
    coordinator.remove(ids)
    #expect(coordinator.shelf.items.isEmpty)
}

@Test @MainActor func shelfCoordinatorGivesUrlsInSelectionOrder() {
    let dir = shelfDir()
    let coordinator = ShelfCoordinator(index: ShelfIndex(fileURL: dir.appendingPathComponent("shelf.json")))
    coordinator.add([u("/tmp/a.pdf"), u("/tmp/b.pdf")], now: now)
    let ids = coordinator.shelf.items.map(\.id)
    let reversed = Array(ids.reversed())
    #expect(coordinator.urls(for: reversed).map(\.lastPathComponent)
        == coordinator.urls(for: ids).map(\.lastPathComponent).reversed())
}

@Test @MainActor func shelfCoordinatorIgnoresEmptyDrop() {
    let dir = shelfDir()
    let coordinator = ShelfCoordinator(index: ShelfIndex(fileURL: dir.appendingPathComponent("shelf.json")))
    coordinator.add([], now: now)
    #expect(coordinator.shelf.items.isEmpty)
}

@Test func airDropAcceptsAnExistingFile() {
    let file = shelfDir().appendingPathComponent("a.pdf")
    touch(file)
    #expect(AirDropSender.canSend([file]))
}
