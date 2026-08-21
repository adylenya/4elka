import Testing
import Foundation
import AppKit
@testable import ChelkaCore

/// Настройки бесполезны, если их никто не читает. Здесь проверяется, что
/// изменённое значение доходит до подсистемы, а не только лежит в файле.

private func snapshot(_ text: String, app: String?) -> PasteboardSnapshot {
    PasteboardSnapshot(changeCount: 1, types: ["public.utf8-plain-text"], text: text,
                       imageData: nil, imageExtension: nil, fileURLs: [], sourceBundleID: app)
}

private func textItem(_ body: String, pinned: Bool = false) -> ClipItem {
    ClipItem(id: UUID(), kind: .text(body), sourceAppBundleID: nil, createdAt: Date(),
             contentHash: body, isPinned: pinned)
}

/// Живые настройки в тесте: замыкание отдаёт текущее значение, а не копию,
/// снятую в момент сборки подсистемы.
private final class SettingsBox {
    var value = Settings.defaults
}

/// Что увидел обработчик изменения и сколько раз его позвали.
private final class SeenBox {
    var seen: Settings?
    var calls = 0
}

// MARK: - Правила игнора

@Test func blockedListFromSettingsStopsTheApp() {
    var s = Settings.defaults
    s.blockedBundleIDs = ["com.example.secret"]
    let rules = s.ignoreRules
    #expect(rules.decide(types: [], sourceBundleID: "com.example.secret", byteCount: 10).reason
            == .blockedApp)
    #expect(rules.decide(types: [], sourceBundleID: "com.apple.Safari", byteCount: 10).shouldStore)
}

@Test func imageCeilingFromSettingsRejectsBigPictures() {
    var s = Settings.defaults
    s.maxImageMegabytes = 1
    let rules = s.ignoreRules
    // Тип обязателен: у текста и у картинки разные пределы, и потолок из
    // настроек относится именно к картинке. Раньше тест передавал пустой список
    // типов и потому проверял вовсе не то, что обещает названием.
    let picture = [NSPasteboard.PasteboardType.png.rawValue]
    #expect(rules.decide(types: picture, sourceBundleID: nil, byteCount: 2 * 1024 * 1024).reason
            == .tooLarge)
    #expect(rules.decide(types: picture, sourceBundleID: nil, byteCount: 500).shouldStore)
    // Текст мерится своим пределом, и потолок картинки его не задевает.
    #expect(rules.decide(types: [], sourceBundleID: nil, byteCount: 2 * 1024 * 1024).shouldStore)
}

/// Собственные записи отбрасываются при любых настройках: этот признак идёт
/// не из настроек, а из идентификатора самого приложения.
@Test func ownWritesStayIgnoredWhateverTheSettings() {
    var s = Settings.defaults
    s.blockedBundleIDs = ["com.example.secret"]
    #expect(s.ignoreRules.decide(types: [], sourceBundleID: Config.ownBundleID,
                                 byteCount: 10).reason == .ownApp)
}

// MARK: - Квоты истории

@Test func quotasFromSettingsLimitTheStore() {
    let quotas = HistoryQuotas(text: 3, image: 1, files: 1)
    var store = HistoryStore()
    for i in 0..<10 { store = store.inserting(textItem("t\(i)"), quotas: quotas) }
    #expect(store.items.count == 3)
}

@Test func loweredQuotaTrimsExistingHistoryAtOnce() {
    var store = HistoryStore()
    for i in 0..<10 { store = store.inserting(textItem("t\(i)")) }
    let trimmed = store.applyingQuotas(HistoryQuotas(text: 2, image: 1, files: 1))
    #expect(trimmed.items.count == 2)
    // Остаются самые свежие, а не первые попавшиеся.
    #expect(trimmed.items.first?.contentHash == "t9")
}

@Test func loweredQuotaStillKeepsPinnedItems() {
    var store = HistoryStore(items: [textItem("важное", pinned: true)])
    for i in 0..<10 { store = store.inserting(textItem("t\(i)")) }
    let trimmed = store.applyingQuotas(HistoryQuotas(text: 1, image: 1, files: 1))
    #expect(trimmed.items.contains { $0.contentHash == "важное" })
}

// MARK: - Карточки

@MainActor
private func center(_ settings: Settings) -> ActivityCenter {
    ActivityCenter(panelState: { .hidden }, settings: { settings })
}

@MainActor
@Test func cardSourceToggleDropsTheEventEntirely() {
    var off = Settings.defaults
    off.cardsFromClipboard = false
    let quiet = center(off)
    quiet.submit(ActivityEvent(kind: .clipboard, title: "текст"), now: Date())
    #expect(quiet.queue.current == nil)

    let loud = center(Settings.defaults)
    loud.submit(ActivityEvent(kind: .clipboard, title: "текст"), now: Date())
    #expect(loud.queue.current != nil)
}

/// Выключенный источник не должен и перебивать показанное: событие обязано
/// пропасть на входе, а не проиграть по приоритету и тем самым сработать,
/// окажись оно приоритетнее.
@MainActor
@Test func disabledSourceCannotEvenOverrideAShownCard() {
    var off = Settings.defaults
    off.cardsFromBattery = false
    let c = center(off)
    let now = Date()
    c.submit(ActivityEvent(kind: .clipboard, title: "текст"), now: now)
    c.submit(ActivityEvent(kind: .battery, title: "заряд"), now: now)
    #expect(c.queue.current?.title == "текст")
}

@MainActor
@Test func cardLifetimeFollowsSettings() {
    var s = Settings.defaults
    s.activityDuration = 10
    let c = center(s)
    let now = Date()
    c.submit(ActivityEvent(kind: .clipboard, title: "текст"), now: now)
    c.tick(now: now.addingTimeInterval(4))
    #expect(c.queue.current != nil)
    c.tick(now: now.addingTimeInterval(11))
    #expect(c.queue.current == nil)
}

// MARK: - Координатор буфера: живые настройки и очистка

@MainActor
private func makeCoordinator(_ settings: @escaping () -> Settings)
    -> (ClipboardCoordinator, BlobStore, URL) {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("chelka-settings-\(UUID().uuidString)")
    let blobs = BlobStore(root: dir.appendingPathComponent("blobs"))
    let index = HistoryIndex(fileURL: dir.appendingPathComponent("index.json"), blobs: blobs)
    let capture = ClipboardCapture(rules: { settings().ignoreRules }, blobs: blobs,
                                   quotas: { settings().historyQuotas })
    let coordinator = ClipboardCoordinator(capture: capture, index: index, blobs: blobs,
                                           activity: ActivityCenter(panelState: { .hidden },
                                                                    settings: settings),
                                           dragRoot: dir.appendingPathComponent("drag"))
    return (coordinator, blobs, dir)
}

@MainActor
@Test func changedBlockListTakesEffectWithoutRestart() {
    let box = SettingsBox()
    let (coordinator, _, _) = makeCoordinator { box.value }

    coordinator.handle(snapshot("первое", app: "com.example.editor"), now: Date())
    #expect(coordinator.history.items.count == 1)

    box.value.blockedBundleIDs = ["com.example.editor"]
    coordinator.handle(snapshot("второе", app: "com.example.editor"), now: Date())
    #expect(coordinator.history.items.count == 1)
}

@MainActor
@Test func changedQuotaTakesEffectWithoutRestart() {
    let box = SettingsBox()
    box.value.textLimit = 2
    let (coordinator, _, _) = makeCoordinator { box.value }
    for i in 0..<5 {
        coordinator.handle(snapshot("t\(i)", app: "com.example.editor"), now: Date())
    }
    #expect(coordinator.history.items.count == 2)
}

@MainActor
@Test func clearHistoryWipesRecordsAndFilesOnDisk() throws {
    let (coordinator, blobs, dir) = makeCoordinator { .defaults }
    let png = Data([0x89, 0x50, 0x4E, 0x47])
    let name = try blobs.write(png, extension: "png")
    coordinator.handle(snapshot("текст", app: "com.example.editor"), now: Date())
    #expect(coordinator.history.items.count == 1)
    #expect(blobs.exists(name))

    coordinator.clearHistory()
    #expect(coordinator.history.items.isEmpty)
    // Осиротевших файлов после очистки остаться не должно.
    #expect(!blobs.exists(name))
    let leftovers = (try? FileManager.default.contentsOfDirectory(
        atPath: dir.appendingPathComponent("blobs").path)) ?? []
    #expect(leftovers.isEmpty)
    // Индекс на диске тоже пуст: перезапуск не должен вернуть стёртое.
    let index = HistoryIndex(fileURL: dir.appendingPathComponent("index.json"), blobs: blobs)
    #expect(index.load().items.isEmpty)
}

@MainActor
@Test func clearHistoryRemovesPinnedItemsToo() {
    let (coordinator, _, _) = makeCoordinator { .defaults }
    coordinator.handle(snapshot("важное", app: "com.example.editor"), now: Date())
    guard let id = coordinator.history.items.first?.id else {
        #expect(Bool(false), "элемент не попал в историю")
        return
    }
    coordinator.pin(id)
    coordinator.clearHistory()
    #expect(coordinator.history.items.isEmpty)
}

@MainActor
@Test func applyingQuotasThroughCoordinatorDeletesEvictedBlobs() throws {
    let (coordinator, blobs, _) = makeCoordinator { .defaults }
    let pngs = [Data([1]), Data([2])]
    for data in pngs {
        coordinator.handle(PasteboardSnapshot(changeCount: 1, types: ["public.png"], text: nil,
                                              imageData: data, imageExtension: "png",
                                              fileURLs: [], sourceBundleID: "com.example.editor"),
                           now: Date())
    }
    let names = coordinator.history.items.compactMap(\.blobName)
    #expect(names.count == 2)

    coordinator.applyQuotas(HistoryQuotas(text: 200, image: 1, files: 50))
    #expect(coordinator.history.items.count == 1)
    let survivor = coordinator.history.items.compactMap(\.blobName)
    let evicted = names.filter { !survivor.contains($0) }
    #expect(evicted.count == 1)
    #expect(evicted.allSatisfy { !blobs.exists($0) })
    #expect(survivor.allSatisfy { blobs.exists($0) })
}

// MARK: - Управляющий настройками

@MainActor
@Test func controllerSanitizesPersistsAndNotifies() {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("controller-\(UUID().uuidString).json")
    let controller = SettingsController(store: SettingsStore(fileURL: url))
    let box = SeenBox()
    controller.onChange = { box.seen = $0 }

    controller.update { current in
        var next = current
        next.batteryLow = 90
        next.batteryHigh = 10
        return next
    }
    #expect(controller.settings.batteryLow < controller.settings.batteryHigh)
    #expect(box.seen == controller.settings)
    #expect(SettingsStore(fileURL: url).load() == controller.settings)
}

@MainActor
@Test func controllerStaysSilentWhenNothingChanged() {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("controller-quiet-\(UUID().uuidString).json")
    let controller = SettingsController(store: SettingsStore(fileURL: url))
    let counter = SeenBox()
    controller.onChange = { _ in counter.calls += 1 }
    controller.update { $0 }
    #expect(counter.calls == 0)
}

@MainActor
@Test func controllerReadsWhatWasSavedBefore() {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("controller-load-\(UUID().uuidString).json")
    var saved = Settings.defaults
    saved.batteryLow = 33
    SettingsStore(fileURL: url).save(saved)
    #expect(SettingsController(store: SettingsStore(fileURL: url)).settings.batteryLow == 33)
}
